//
//  FileManager.swift
//
//  Created by Imthath M on 21/04/20.
//  Copyright © 2020 SkyDevz. All rights reserved.
//

import Foundation

public class Console {
  internal static let shared = Console()

  private init() { }

  public func log(file: String = #file,
                  functionName: String = #function,
                  lineNumber: Int = #line, _ message: String) {
    print("\(URL(fileURLWithPath: file).lastPathComponent)-\(functionName):\(lineNumber)  \(message)")
  }
}

let logger: Console = Console.shared

public class FileIO {

  private static var encoder: JSONEncoder { JSONEncoder() }
  private static var decoder: JSONDecoder { JSONDecoder() }

  public static func getObject<T: Codable>(inBundle bundle: Bundle = Bundle.main, withName filename: String, ofType type: FileType = .json) -> T? {
    guard let bundlePath = bundle
            .path(forResource: filename, ofType: type.rawValue),
          let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)) else {
      logger.log("No file found or unable to parse file - \(filename)")
      return nil
    }
    return getObject(from: data)
  }

  public static func getObject<T: Codable>(from string: String) -> T? {
    guard let data = string.data(using: .utf8) else {
      logger.log("Unable to convert string to data for type - \(T.self)")
      return nil
    }

    return getObject(from: data)
  }

  private static func getObject<T: Codable>(from data: Data) -> T? {
    var object: T?
    do {
      object = try decoder.decode(T.self, from: data)
      logger.log("Data decoding successfull for type \(T.self)")
    } catch let error as NSError {
      logger.log("unable to decode object from text file: \(error.description)")
    }

    return object
  }

  public static func getOjbectFromFile<T: Codable>(named name: String, withType type: FileType = .json) -> T? {
    var object: T?
    do {
      if let data = readData(from: name, type: type) {
        object = try decoder.decode(T.self, from: data)
        logger.log("object read from file \(name)")
      }
    } catch let error as NSError {
      logger.log("unable to decode object from text file: \(error.description)")
    }

    return object
  }

  public static func save<T>(_ object: T, to name: String, as type: FileType = .json) where T: Codable {
    do {
      encoder.outputFormatting = .prettyPrinted

      let url = try getUrl(of: name, type: type)
      let data = try encoder.encode(object)

      switch type {
      case .text:
        if let text = String(data: data, encoding: .utf8) {
          try text.write(to: url, atomically: true, encoding: .utf8)
          logger.log("Saved text file \(name)")
        }
      case .json:
        try data.write(to: url)
        logger.log("Saved \(name).\(type.rawValue)")
      }

    } catch let error as NSError {
      logger.log("unable to save: \(error.description)")
    }
  }

  public static func readData(from name: String, type: FileType) -> Data? {
    var result: Data?
    do {
      let url = try getUrl(of: name, type: type)
      result = try Data(contentsOf: url)
    } catch let error as NSError {
      logger.log("unable to read data of type \(type.rawValue) from file \(name)")
      logger.log("Error: \(error.description)")
    }
    return result
  }

  public static func readText(from name: String) -> String? {
    var result: String?
    do {
      let url = try getUrl(of: name)
      result = try String(contentsOf: url)
    } catch let error as NSError {
      logger.log("unable to read text from file \(name)")
      logger.log("Error: \(error.description)")
    }
    return result
  }

  public static func deleteFile(withName name: String, type: FileType = .json) {
    if let url = try? getUrl(of: name, type: type) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  public static func getUrl(of name: String, type: FileType = .json) throws -> URL {
    let docDirectoryUrl = try FileManager.default.url(for: .documentDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
    return docDirectoryUrl.appendingPathComponent(name).appendingPathExtension(type.rawValue)
  }
}

public enum FileType: String {
  case text = "txt"
  case json = "json"
}

@propertyWrapper
public struct Default<T> {
  let key: String
  let defaultValue: T

  public init(_ key: String, defaultValue: T) {
    self.key = key
    self.defaultValue = defaultValue
  }

  public var wrappedValue: T {
    get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
    set { UserDefaults.standard.set(newValue, forKey: key) }
  }
}
