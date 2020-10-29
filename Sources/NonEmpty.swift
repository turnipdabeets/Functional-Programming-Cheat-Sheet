import Foundation

public struct NonEmpty<C: Collection> {
  public typealias Element = C.Element

  public internal(set) var head: Element
  public internal(set) var tail: C

  public init(_ head: Element, _ tail: C) {
    self.head = head
    self.tail = tail
  }
}

extension NonEmpty: CustomStringConvertible {
  public var description: String {
    return "\(self.head)\(self.tail)"
  }
}

extension NonEmpty: Equatable where C: Equatable, C.Element: Equatable {}

extension NonEmpty: Hashable where C: Hashable, C.Element: Hashable {}

extension NonEmpty: Decodable where C: Decodable, C.Element: Decodable {}

extension NonEmpty: Encodable where C: Encodable, C.Element: Encodable {}

public typealias NonEmptyArray<Element> = NonEmpty<[Element]>

extension NonEmpty: Collection {
  public enum Index: Comparable {
    case head
    case tail(C.Index)

    public static func < (lhs: Index, rhs: Index) -> Bool {
      switch (lhs, rhs) {
      case let (.tail(l), .tail(r)):
        return l < r
      case (.head, .tail):
        return true
      case (.tail, .head), (.head, .head):
        return false
      }
    }
  }

  public var startIndex: Index {
    return .head
  }

  public var endIndex: Index {
    return .tail(self.tail.endIndex)
  }

  public subscript(position: Index) -> Element {
    switch position {
    case .head:
      return self.head
    case let .tail(index):
      return self.tail[index]
    }
  }

  public func index(after i: Index) -> Index {
    switch i {
    case .head:
      return .tail(self.tail.startIndex)
    case let .tail(index):
      return .tail(self.tail.index(after: index))
    }
  }
}

extension NonEmpty {
  #if swift(>=4.1.5)
  public var first: Element {
    return self.head
  }

  @available(swift, obsoleted: 4.1.5, renamed: "first")
  public var safeFirst: Element {
    return self.head
  }
  #else
  public var safeFirst: Element {
    return self.head
  }
  #endif

  public func flatMap<T>(_ transform: (Element) throws -> NonEmpty<[T]>) rethrows -> NonEmpty<[T]> {
    var result = try transform(self.head)
    for element in self.tail {
      try result.append(contentsOf: transform(element))
    }
    return result
  }

  public func map<T>(_ transform: (Element) throws -> T) rethrows -> NonEmpty<[T]> {
    return try NonEmpty<[T]>(transform(self.head), self.tail.map(transform))
  }

  public func max(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
    return try self.tail
      .max(by: areInIncreasingOrder)
      .map { try areInIncreasingOrder(self.head, $0) ? $0 : self.head } ?? self.head
  }

  public func min(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element {
    return try self.tail
      .min(by: areInIncreasingOrder)
      .map { try areInIncreasingOrder(self.head, $0) ? self.head : $0 } ?? self.head
  }

  public func sorted(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> NonEmpty<[Element]> {
    var result = ContiguousArray(self)
    try result.sort(by: areInIncreasingOrder)
    return NonEmpty<[Element]>(result.first ?? self.head, Array(result.dropFirst()))
  }
}

extension NonEmpty where C.Index == Int {
  public subscript(position: Int) -> Element {
    return self[position == 0 ? .head : .tail(self.tail.startIndex + position - 1)]
  }
}

extension NonEmpty: Comparable where C: Comparable, C.Element: Comparable {
  public static func < (lhs: NonEmpty, rhs: NonEmpty) -> Bool {
    return lhs.head < rhs.head && lhs.tail < rhs.tail
  }
}

extension NonEmpty where C.Element: Comparable {
  public func max() -> Element {
    return Swift.max(self.head, self.tail.max() ?? self.head)
  }

  public func min() -> Element {
    return Swift.min(self.head, self.tail.min() ?? self.head)
  }

  public func sorted() -> NonEmpty<[Element]> {
    var result = ContiguousArray(self)
    result.sort()
    return NonEmpty<[Element]>(result.first ?? self.head, Array(result.dropFirst()))
  }
}

public typealias NonEmptyDictionary<Key, Value> = NonEmpty<[Key: Value]> where Key: Hashable

public protocol _DictionaryProtocol: Collection where Element == (key: Key, value: Value) {
  associatedtype Key: Hashable
  associatedtype Value
  var keys: Dictionary<Key, Value>.Keys { get }
  subscript(key: Key) -> Value? { get }
  mutating func merge<S: Sequence>(
    _ other: S, uniquingKeysWith combine: (Value, Value) throws -> Value
    ) rethrows where S.Element == (Key, Value)
  mutating func merge(
    _ other: [Key: Value], uniquingKeysWith combine: (Value, Value) throws -> Value
    ) rethrows
  @discardableResult mutating func removeValue(forKey key: Key) -> Value?
  mutating func updateValue(_ value: Value, forKey key: Key) -> Value?
}

extension Dictionary: _DictionaryProtocol {}

extension NonEmpty where C: _DictionaryProtocol {
  public init(_ head: Element, _ tail: C) {
    guard !tail.keys.contains(head.0) else { fatalError("Dictionary contains duplicate key") }
    self.head = head
    self.tail = tail
  }

  public init(
    _ head: Element,
    _ tail: C,
    uniquingKeysWith combine: (C.Value, C.Value) throws -> C.Value
    )
    rethrows {

      var tail = tail
      if let otherValue = tail.removeValue(forKey: head.0) {
        self.head = (head.0, try combine(head.1, otherValue))
      } else {
        self.head = head
      }
      self.tail = tail
  }

  public subscript(key: C.Key) -> C.Value? {
    return self.head.0 == key ? self.head.1 : self.tail[key]
  }

  public mutating func merge<S: Sequence>(
    _ other: S,
    uniquingKeysWith combine: (C.Value, C.Value) throws -> C.Value
    ) rethrows
    where S.Element == (C.Key, C.Value) {

      if let otherValue = other.first(where: { key, _ in key == self.head.0 })?.1 {
        self.head.1 = try combine(self.head.1, otherValue)
      }
      try self.tail.merge(other, uniquingKeysWith: combine)
  }

  public func merging<S: Sequence>(
    _ other: S,
    uniquingKeysWith combine: (C.Value, C.Value) throws -> C.Value
    ) rethrows
    -> NonEmpty
    where S.Element == (C.Key, C.Value) {

      var copy = self
      try copy.merge(other, uniquingKeysWith: combine)
      return copy
  }

  public mutating func merge(
    _ other: [C.Key: C.Value],
    uniquingKeysWith combine: (C.Value, C.Value) throws -> C.Value
    ) rethrows {

    var other = other
    if let otherValue = other.removeValue(forKey: self.head.0) {
      self.head.1 = try combine(self.head.1, otherValue)
    }
    try self.tail.merge(other, uniquingKeysWith: combine)
  }

  public func merging(
    _ other: [C.Key: C.Value],
    uniquingKeysWith combine: (C.Value, C.Value) throws -> C.Value
    ) rethrows
    -> NonEmpty {

      var copy = self
      try copy.merge(other, uniquingKeysWith: combine)
      return copy
  }

  public mutating func updateValue(_ value: C.Value, forKey key: C.Key)
    -> C.Value? {

      if head.0 == key {
        let oldValue = head.1
        head.1 = value
        return oldValue
      } else {
        return tail.updateValue(value, forKey: key)
      }
  }
}

extension NonEmpty where C: _DictionaryProtocol, C.Value: Equatable {
  public static func == (lhs: NonEmpty, rhs: NonEmpty) -> Bool {
    return Dictionary(uniqueKeysWithValues: Array(lhs))
      == Dictionary(uniqueKeysWithValues: Array(rhs))
  }
}

extension NonEmpty where C: _DictionaryProtocol & ExpressibleByDictionaryLiteral {
  public init(_ head: Element) {
    self.head = head
    self.tail = [:]
  }
}

extension NonEmpty: MutableCollection where C: MutableCollection {
  public subscript(position: Index) -> Element {
    get {
      switch position {
      case .head:
        return self.head
      case let .tail(index):
        return self.tail[index]
      }
    }
    set {
      switch position {
      case .head:
        self.head = newValue
      case let .tail(index):
        self.tail[index] = newValue
      }
    }
  }
}

extension NonEmpty where C: MutableCollection, C.Index == Int {
  public subscript(position: Int) -> Element {
    get {
      return self[position == 0 ? .head : .tail(self.tail.startIndex + position - 1)]
    }
    set {
      self[position == 0 ? .head : .tail(self.tail.startIndex + position - 1)] = newValue
    }
  }
}

extension NonEmpty {
  public func randomElement<T: RandomNumberGenerator>(using generator: inout T) -> Element {
    return ContiguousArray(self).randomElement(using: &generator) ?? self.head
  }

  public func randomElement() -> Element {
    var generator = SystemRandomNumberGenerator()
    return self.randomElement(using: &generator)
  }
}

extension NonEmpty where C: RangeReplaceableCollection {
  public mutating func shuffle<T: RandomNumberGenerator>(using generator: inout T) {
    let result = ContiguousArray(self).shuffled(using: &generator)
    self.head = result.first ?? self.head
    self.tail = C(result.dropFirst())
  }

  public mutating func shuffle() {
    var generator = SystemRandomNumberGenerator()
    self.shuffle(using: &generator)
  }

  public func shuffled<T: RandomNumberGenerator>(using generator: inout T) -> NonEmpty {
    var copy = self
    copy.shuffle(using: &generator)
    return copy
  }

  public func shuffled() -> NonEmpty {
    var generator = SystemRandomNumberGenerator()
    return self.shuffled(using: &generator)
  }
}

extension NonEmpty where C: RangeReplaceableCollection {
  public init(_ head: Element, _ tail: Element...) {
    self.init(head, C(tail))
  }

  public mutating func append(_ newElement: Element) {
    self.tail.append(newElement)
  }

  public mutating func append<S: Sequence>(contentsOf newElements: S) where Element == S.Element {
    self.tail.append(contentsOf: newElements)
  }

  public mutating func insert(_ newElement: Element, at i: Index) {
    switch i {
    case .head:
      self.tail.insert(self.head, at: self.tail.startIndex)
      self.head = newElement
    case let .tail(index):
      self.tail.insert(newElement, at: self.tail.index(after: index))
    }
  }

  public mutating func insert<S>(contentsOf newElements: S, at i: Index)
    where S: Collection, Element == S.Element {

      switch i {
      case .head:
        guard let first = newElements.first else { return }
        var tail = C(newElements.dropFirst())
        tail.append(self.head)
        self.tail.insert(contentsOf: tail, at: self.tail.startIndex)
        self.head = first
      case let .tail(index):
        self.tail.insert(contentsOf: newElements, at: self.tail.index(after: index))
      }
  }

  public static func + <S: Sequence>(lhs: NonEmpty, rhs: S) -> NonEmpty where Element == S.Element {
    var tail = lhs.tail
    tail.append(contentsOf: rhs)
    return NonEmpty(lhs.head, tail)
  }

  public static func += <S: Sequence>(lhs: inout NonEmpty, rhs: S) where Element == S.Element {
    lhs.append(contentsOf: rhs)
  }
}

extension NonEmpty where C: RangeReplaceableCollection, C.Index == Int {
  public mutating func insert(_ newElement: Element, at i: Int) {
    self.insert(newElement, at: i == self.tail.startIndex ? .head : .tail(i - 1))
  }

  public mutating func insert<S>(contentsOf newElements: S, at i: Int)
    where S: Collection, Element == S.Element {

      self.insert(contentsOf: newElements, at: i == self.tail.startIndex ? .head : .tail(i - 1))
  }
}

extension NonEmpty {
  public func joined<S: Sequence, RRC: RangeReplaceableCollection>(
    separator: S
    )
    -> NonEmpty<RRC>
    where Element == NonEmpty<RRC>, S.Element == RRC.Element {

      return NonEmpty<RRC>(
        self.head.head, self.head.tail + RRC(separator) + RRC(self.tail.joined(separator: separator))
      )
  }

  public func joined<RRC: RangeReplaceableCollection>() -> NonEmpty<RRC> where Element == NonEmpty<RRC> {
      return joined(separator: RRC())
  }
}

public typealias NonEmptySet<Element> = NonEmpty<Set<Element>> where Element: Hashable & Comparable

extension NonEmpty where C: SetAlgebra, C.Element: Hashable & Comparable {
  public init(_ head: Element, _ tail: C) {
    var tail = tail
    tail.insert(head)
    self.head = tail.min() ?? head
    tail.remove(self.head)
    self.tail = tail
  }

  public init(_ head: Element, _ tail: Element...) {
    self.init(head, C(tail))
  }

  public func contains(_ member: Element) -> Bool {
    var tail = self.tail
    tail.insert(self.head)
    return tail.contains(member)
  }

  public func union(_ other: NonEmpty) -> NonEmpty {
    var copy = self
    copy.formUnion(other)
    return copy
  }

  public func union(_ other: C) -> NonEmpty {
    var copy = self
    copy.formUnion(other)
    return copy
  }

  public func intersection(_ other: NonEmpty) -> C {
    var tail = self.tail
    tail.insert(self.head)
    var otherTail = other.tail
    otherTail.insert(other.head)
    return tail.intersection(otherTail)
  }

  public func intersection(_ other: C) -> C {
    var tail = self.tail
    tail.insert(self.head)
    return tail.intersection(other)
  }

  public func symmetricDifference(_ other: NonEmpty) -> C {
    var tail = self.tail
    tail.insert(self.head)
    var otherTail = other.tail
    otherTail.insert(other.head)
    return tail.symmetricDifference(otherTail)
  }

  public func symmetricDifference(_ other: C) -> C {
    var tail = self.tail
    tail.insert(self.head)
    return tail.symmetricDifference(other)
  }

  @discardableResult
  public mutating func insert(_ newMember: Element)
    -> (inserted: Bool, memberAfterInsert: Element) {

      var newMember = newMember
      if newMember < self.head {
        (self.head, newMember) = (newMember, self.head)
      }
      var (inserted, memberAfterInsert) = self.tail.insert(newMember)
      if let _ = self.tail.remove(self.head) {
        (inserted, self.head) = (false, memberAfterInsert)
      }
      return (inserted, memberAfterInsert)
  }

// TODO: Implement
//  @discardableResult
//  public mutating func update(with newMember: Collection.Element) -> Collection.Element? {
//    fatalError()
//  }

  public mutating func formUnion(_ other: NonEmpty) {
    self.tail.insert(self.head)
    self.tail.insert(other.head)
    self.tail.formUnion(other.tail)
    self.head = tail.min() ?? self.head
    self.tail.remove(self.head)
  }

  public mutating func formUnion(_ other: C) {
    self.tail.insert(self.head)
    self.tail.formUnion(other)
    self.head = tail.min() ?? self.head
    self.tail.remove(self.head)
  }

  public func subtracting(_ other: NonEmpty) -> C {
    var tail = self.tail
    tail.insert(self.head)
    tail.remove(other.head)
    return tail.subtracting(other.tail)
  }

  public func subtracting(_ other: C) -> C {
    var tail = self.tail
    tail.insert(self.head)
    return tail.subtracting(other)
  }

  public func isDisjoint(with other: NonEmpty) -> Bool {
    var (tail, otherTail) = (self.tail, other.tail)
    tail.insert(self.head)
    otherTail.insert(other.head)
    return tail.isDisjoint(with: otherTail)
  }

  public func isDisjoint(with other: C) -> Bool {
    var tail = self.tail
    tail.insert(self.head)
    return tail.isDisjoint(with: other)
  }

  public func isSubset(of other: NonEmpty) -> Bool {
    var (tail, otherTail) = (self.tail, other.tail)
    tail.insert(self.head)
    otherTail.insert(other.head)
    return tail.isSubset(of: otherTail)
  }

  public func isSubset(of other: C) -> Bool {
    var tail = self.tail
    tail.insert(self.head)
    return tail.isSubset(of: other)
  }

  public func isSuperset(of other: NonEmpty) -> Bool {
    var (tail, otherTail) = (self.tail, other.tail)
    tail.insert(self.head)
    otherTail.insert(other.head)
    return tail.isSuperset(of: otherTail)
  }

  public func isSuperset(of other: C) -> Bool {
    var tail = self.tail
    tail.insert(self.head)
    return tail.isSuperset(of: other)
  }

  public func isStrictSubset(of other: NonEmpty) -> Bool {
    var (tail, otherTail) = (self.tail, other.tail)
    tail.insert(self.head)
    otherTail.insert(other.head)
    return tail.isStrictSubset(of: otherTail)
  }

  public func isStrictSubset(of other: C) -> Bool {
    var tail = self.tail
    tail.insert(self.head)
    return tail.isStrictSubset(of: other)
  }

  public func isStrictSuperset(of other: NonEmpty) -> Bool {
    var (tail, otherTail) = (self.tail, other.tail)
    tail.insert(self.head)
    otherTail.insert(other.head)
    return tail.isStrictSuperset(of: otherTail)
  }

  public func isStrictSuperset(of other: C) -> Bool {
    var tail = self.tail
    tail.insert(self.head)
    return tail.isStrictSuperset(of: other)
  }
}

public typealias NonEmptyString = NonEmpty<String>

extension NonEmpty where C == String {
  public init(_ head: Character) {
    self.init(head, "")
  }

  public func lowercased() -> NonEmptyString {
    return NonEmpty(String(self.head).lowercased().first!, self.tail.lowercased())
  }

  public func uppercased() -> NonEmptyString {
    return NonEmpty(String(self.head).uppercased().first!, self.tail.uppercased())
  }

  public init<S: LosslessStringConvertible>(_ value: S) {
    let string = String(value)
    self.init(string.first!, String(string.dropFirst()))
  }

  public var string: String {
    return String(self.head) + self.tail
  }
}
