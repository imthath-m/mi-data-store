//
//  MICoreData.swift
//
//  Created by @imthath_m on 20/09/19.
//  Copyright © 2019 Imthath M. All rights reserved.
//

import Foundation
import CoreData

open class BaseStore: CoreDataStorable {
  public var loadstoreByDefault: Bool = true
	open var modelName: String

  public init(modelName: String) {
		self.modelName = modelName
	}

  lazy public var persistantContainer: NSPersistentContainer = makeContainer()

  lazy public var mainContext: NSManagedObjectContext = persistantContainer.viewContext

  lazy public var privateContextWithParent: NSManagedObjectContext = mainContext.privateChildContext

  open func makeContainer() -> NSPersistentContainer {
    let container: NSPersistentCloudKitContainer = NSPersistentCloudKitContainer(name: modelName)

    guard loadstoreByDefault else {
      return container
    }

    container.loadPersistentStores { storeDesc, error in
      if let error = error {
        assertionFailure(error.localizedDescription)
      }

      if let url = storeDesc.url {
        print("URL - " + url.absoluteString)
      } else {
        assertionFailure("No Store URL")
      }
    }
    return container
  }
}

public protocol CoreDataStorable {
  var modelName: String { get }
  var persistantContainer: NSPersistentContainer { get }
  var mainContext: NSManagedObjectContext { get }
  var privateContextWithParent : NSManagedObjectContext { get }
  var currentContext: NSManagedObjectContext { get }
  func saveChanges()
}

public extension CoreDataStorable {
  var currentContext: NSManagedObjectContext {
    Thread.isMainThread ? mainContext : privateContextWithParent
  }

  func saveChanges() {
    if Thread.isMainThread {
      mainContext.saveChanges()
    } else {
      privateContextWithParent.savePrivateAndParent()
    }
  }

  func loadStore(onCompletion handler: ((NSPersistentStoreDescription, Error?) -> Void)? = nil) {
    persistantContainer.loadPersistentStores(completionHandler: { desc, error in
      if let error = error {
        assertionFailure(error.localizedDescription)
      }
      handler?(desc, error)
    })
  }
}

extension NSManagedObjectContext {

  convenience public init?(modelName: String, in bundle: Bundle) {

    guard let objectModel = NSManagedObjectModel(modelName: modelName, in: bundle) else {
      return nil
    }

    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: objectModel)

    do {
      try coordinator.loadStore(withName: modelName)
    } catch {
      return nil
    }

    self.init(coordinator: coordinator)
  }

  convenience private init(coordinator: NSPersistentStoreCoordinator) {
    self.init(concurrencyType: .privateQueueConcurrencyType)
    self.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    self.persistentStoreCoordinator = coordinator
  }

  public func update() {
    if hasChanges {
      do {
        try save()
      } catch {
        //                "❌❌❌ Failed to save data".log()
      }
    }
  }

  public var privateChildContext: NSManagedObjectContext {

    let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    privateContext.parent = self
    privateContext.shouldDeleteInaccessibleFaults = true

    if #available(iOS 10.0, *) {
      privateContext.mergePolicy =  NSMergePolicy.mergeByPropertyObjectTrump
    } else {
      // Fallback on earlier versions
      privateContext.mergePolicy = NSMergePolicy.init(merge: NSMergePolicyType.mergeByPropertyObjectTrumpMergePolicyType)
    }

    return privateContext
  }

  public func clearAllObjects(forEntityNames entityNames: [String]) {
    entityNames.forEach { clearObjects(withName: $0) }
  }

  public func clearObjects(withName entityName: String, using predicate: NSPredicate? = nil) {
    self.performAndWait {
      let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
      fetchRequest.predicate = predicate
      let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
      deleteRequest.resultType = .resultTypeObjectIDs

      var deleteResult: NSBatchDeleteResult?

      do {
        deleteResult = try self.execute(deleteRequest) as? NSBatchDeleteResult
        debugPrint("✅✅✅ Deleted batch of entity \(entityName) successfully")

        //Since it is deleting the records directly from persistent store,
        // we need to manually update the deleted changes to managed object context
        // REF: https://developer.apple.com/library/content/featuredarticles/CoreData_Batch_Guide/BatchDeletes/BatchDeletes.html
        let objectIDs = deleteResult?.result as? [NSManagedObjectID]
        if let objectIDArray = objectIDs {
          let changes = [NSDeletedObjectsKey : objectIDArray]
          NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
        }

        self.saveChanges()
      } catch {
        debugPrint("❌❌❌ Failed to execute batch delete request in entity \(entityName): \(error)")
      }
    }
  }

  @discardableResult
  public func savePrivateAndParent() -> Bool {

    guard saveChanges(inContextName: "Private context"),
          let parentContext = self.parent else { return false }

    return parentContext.saveChanges(inContextName: "Parent context")
  }

  @discardableResult
  public func saveChanges(inContextName context: String = "Context") -> Bool {
    var isSuccess = true

    self.performAndWait {
      guard let persistentStores = self.persistentStoreCoordinator?.persistentStores.count, persistentStores > 0  else {
        debugPrint("❌❌❌ Failed to find Persistent store to save \(context)")
        isSuccess = false
        return
      }
      do {
        try self.save()
        debugPrint("✅✅✅ \(context) saved successfully")
      } catch {
        debugPrint("❌❌❌ Failed to save \(context) - \(error.localizedDescription)")
        isSuccess = false
      }
    }
    return isSuccess
  }

  public func fetchAndWait<ManagedObject: NSFetchRequestResult>(_ request: NSFetchRequest<ManagedObject>) -> [ManagedObject] {
    var results = [ManagedObject]()
    self.performAndWait {
      do {
        results = try self.fetch(request)
        //                debugPrint("✅✅✅ Fetched results of type \(ManagedObject.self) successfully")
      } catch {
        debugPrint("❌❌❌ Failed to fetch type \(ManagedObject.self)")
      }

    }
    return results
  }
}

private extension NSManagedObjectModel {

  convenience init?(modelName: String, in bundle: Bundle) {
    guard let modelURL = bundle.url(forResource: modelName,
                                    withExtension: "momd") else {
      return nil
    }

    self.init(contentsOf: modelURL)
  }
}

private extension NSPersistentStoreCoordinator {

  func loadStore(withName name: String) throws {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let storeURL = documentsURL.appendingPathComponent("\(name).sqlite")
    let options = [NSInferMappingModelAutomaticallyOption: true,
                   NSMigratePersistentStoresAutomaticallyOption: true]
    try addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
  }
}

public extension NSEntityDescription {
  func addAttribute(name: String, type: NSAttributeType, isUnique: Bool = false) {
    let attribute = NSAttributeDescription()
    attribute.name = name
    attribute.attributeType = type

    if isUnique {
      uniquenessConstraints = [[attribute]]
    }

    properties.append(attribute)
  }
}
