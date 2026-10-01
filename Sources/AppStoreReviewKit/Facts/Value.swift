import Foundation

/// A decoded JSON or property list value, kept `Sendable` so facts can cross isolation boundaries.
public enum Value: Sendable, Equatable, Hashable {
    static let booleanStrings = ["YES": true, "true": true, "1": true, "NO": false, "false": false, "0": false]

    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case array([Value])
    case dictionary([String: Value])
    case null

    public var string: String? {
        if case let .string(value) = self { value } else { nil }
    }

    public var bool: Bool? {
        switch self {
        case let .bool(value): value
        case let .number(value): value != 0
        case let .string(value): Self.booleanStrings[value]
        default: nil
        }
    }

    public var array: [Value]? {
        if case let .array(value) = self { value } else { nil }
    }

    public var dictionary: [String: Value]? {
        if case let .dictionary(value) = self { value } else { nil }
    }

    public var strings: [String] {
        array?.compactMap(\.string) ?? []
    }

    public subscript(key: String) -> Value? {
        dictionary?[key]
    }
}

// MARK: - Conversion
extension Value {
    /// Converts the output of `JSONSerialization` or `PropertyListSerialization`.
    public init(foundation object: Any) {
        switch object {
        case let value as String:
            self = .string(value)
        case let value as NSNumber where CFGetTypeID(value) == CFBooleanGetTypeID():
            self = .bool(value.boolValue)
        case let value as NSNumber:
            self = .number(value.doubleValue)
        case let value as Date:
            self = .date(value)
        case let value as Data:
            self = .data(value)
        case let value as [Any]:
            self = .array(value.map(Value.init(foundation:)))
        case let value as [String: Any]:
            self = .dictionary(value.mapValues(Value.init(foundation:)))
        default:
            self = .null
        }
    }

    public static func parsePropertyList(_ data: Data) throws -> Value {
        Value(foundation: try PropertyListSerialization.propertyList(from: data, format: nil))
    }

    public static func parseJSON(_ data: Data) throws -> Value {
        Value(foundation: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }
}
