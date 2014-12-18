// RUN: %target-run-stdlib-swift | FileCheck %s

import Foundation
import Swift
// ==== Tests =====

func hex(x: UInt64) -> String { return String(x, radix:16) }

func hexAddrVal<T>(x: T) -> String {
  return "@0x" + hex(UInt64(unsafeBitCast(x, Word.self)))
}

func hexAddr(x: AnyObject?) -> String {
  if let owner: AnyObject = x {
    if let y = owner as? _StringBuffer._Storage.Storage {
      return ".Native\(hexAddrVal(y))"
    }
    if let y = owner as? NSString {
      return ".Cocoa\(hexAddrVal(y))"
    }
    else {
      return "?Uknown?\(hexAddrVal(owner))"
    }
  }
  return "null"
}

func repr(x: NSString) -> String {
  return "\(NSStringFromClass(object_getClass(x)))\(hexAddrVal(x)) = \"\(x)\""
}

func repr(x: _StringCore) -> String {
  if x.hasContiguousStorage {
    if let b = x.nativeBuffer {
    var offset = x.elementWidth == 2
      ? UnsafeMutablePointer(b.start) - x.startUTF16
      : UnsafeMutablePointer(b.start) - x.startASCII
      return "Contiguous(owner: "
      + "\(hexAddr(x._owner))[\(offset)...\(x.count + offset)]"
      + ", capacity = \(b.capacity))"
    }
    return "Contiguous(owner: \(hexAddr(x._owner)), count: \(x.count))"
  }
  else if let b2 = x.cocoaBuffer {
    return "Opaque(buffer: \(hexAddr(b2))[0...\(x.count)])"
  }
  return "?????"
}

func repr(x: String) -> String {
  return "String(\(repr(x._core))) = \"\(x)\""
}

// CHECK: Testing
println("Testing...")

//===--------- Native Strings ---------===

// Force the string literal representation into a Native, heap-allocated buffer
var nsb = "🏂☃❅❆❄︎⛄️❄️"
// CHECK-NEXT: Hello, snowy world: 🏂☃❅❆❄︎⛄️❄️
println("Hello, snowy world: \(nsb)")
// CHECK-NEXT: String(Contiguous(owner: null, count: 11))
println("  \(repr(nsb))")

var empty = String()
// CHECK-NEXT: These are empty: <>
println("These are empty: <\(empty)>")
// CHECK-NEXT: String(Contiguous(owner: null, count: 0))
println("  \(repr(empty))")


//===--------- non-ASCII ---------===

func nonASCII() {
  // Cocoa stores non-ASCII in a UTF-16 buffer
  // Code units in each character: 2 1 1 1 2 2 2
  // Offset of each character:     0 2 3 4 5 7 9 11
  var nsUTF16 = NSString(UTF8String: "🏂☃❅❆❄︎⛄️❄️")!
  // CHECK-NEXT: has UTF-16: true
  println("has UTF-16: \(CFStringGetCharactersPtr(unsafeBitCast(nsUTF16, CFString.self)) != nil)")

  // CHECK: --- UTF-16 basic round-tripping ---
  println("--- UTF-16 basic round-tripping ---")

  // check that no extraneous objects are created
  // CHECK-NEXT: __NSCFString@[[utf16address:[x0-9a-f]+]] = "🏂☃❅❆❄︎⛄️❄️"
  println("  \(repr(nsUTF16))")

  // CHECK-NEXT: String(Contiguous(owner: .Cocoa@[[utf16address]], count: 11))
  var newNSUTF16 = nsUTF16 as String
  println("  \(repr(newNSUTF16))")

  // CHECK-NEXT: __NSCFString@[[utf16address]] = "🏂☃❅❆❄︎⛄️❄️"
  var nsRoundTripUTF16: NSString = newNSUTF16
  println("  \(repr(nsRoundTripUTF16))")

  // CHECK: --- UTF-16 slicing ---
  println("--- UTF-16 slicing ---")

  // Slicing the String does not allocate
  // CHECK-NEXT: String(Contiguous(owner: .Cocoa@[[utf16address]], count: 6))
  let i2 = advance(newNSUTF16.startIndex, 2)
  let i8 = advance(newNSUTF16.startIndex, 6)
  println("  \(repr(newNSUTF16[i2..<i8]))")

  // Representing a slice as an NSString requires a new object
  // CHECK-NOT: NSString@[[utf16address]] = "❅❆❄︎⛄️"
  // CHECK-NEXT: _NSContiguousString@[[nsContiguousStringAddress:[x0-9a-f]+]] = "❅❆❄︎⛄️"
  var nsSliceUTF16: NSString = newNSUTF16[i2..<i8]
  println("  \(repr(nsSliceUTF16))")

  // Check that we can recover the original buffer
  // CHECK-NEXT: String(Contiguous(owner: .Cocoa@[[utf16address]], count: 6))
  println("  \(repr(nsSliceUTF16 as String))")
}
nonASCII()

//===--------- ASCII ---------===

func ascii() {
  // Cocoa stores ASCII in a buffer of bytes.  This is an important case
  // because it doesn't provide a contiguous array of UTF-16, so we'll be
  // treating it as an opaque NSString.
  var nsASCII = NSString(UTF8String: "foobar")!
  // CHECK-NEXT: has UTF-16: false
  println("has UTF-16: \(CFStringGetCharactersPtr(unsafeBitCast(nsASCII, CFString.self)) != nil)")

  // CHECK: --- ASCII basic round-tripping ---
  println("--- ASCII basic round-tripping ---")

  // CHECK-NEXT: [[nsstringclass:(__NSCFString|NSTaggedPointerString)]]@[[asciiaddress:[x0-9a-f]+]] = "foobar"
  println("  \(repr(nsASCII))")

  // CHECK-NEXT NO: String(Opaque(buffer: @[[asciiaddress]][0...6]))
  var newNSASCII = nsASCII as String
  // println("  \(repr(newNSASCII))")

  // CHECK-NEXT: [[nsstringclass]]@[[asciiaddress]] = "foobar"
  var nsRoundTripASCII: NSString = newNSASCII
  println("  \(repr(nsRoundTripASCII))")

  // CHECK: --- ASCII slicing ---
  println("--- ASCII slicing ---")

  let i3 = advance(newNSASCII.startIndex, 3)
  let i6 = advance(newNSASCII.startIndex, 6)
  
  // Slicing the String does not allocate
  // XCHECK-NEXT: String(Opaque(buffer: @[[asciiaddress]][3...6]))
  println("  \(repr(newNSASCII[i3..<i6]))")

  // Representing a slice as an NSString requires a new object
  // XCHECK-NOT: NSString@[[asciiaddress]] = "bar"
  // XCHECK-NEXT: _NSOpaqueString@[[nsOpaqueSliceAddress:[x0-9a-f]+]] = "bar"
  var nsSliceASCII: NSString = newNSASCII[i3..<i6]
  println("  \(repr(nsSliceASCII))")

  // When round-tripped back to Swift, the _NSOpaqueString object is the new owner
  // XCHECK-NEXT: String(Opaque(buffer: @[[nsOpaqueSliceAddress]][0...3]))
  println("  \(repr(nsSliceASCII as String))")
}
ascii()

//===-------- Literals --------===

// String literals default to UTF-16.

// CHECK: --- Literals ---
println("--- Literals ---")

// CHECK-NEXT: String(Contiguous(owner: null, count: 6)) = "foobar"
// CHECK-NEXT: true
var asciiLiteral: String = "foobar"
println("  \(repr(asciiLiteral))")
println("  \(asciiLiteral._core.isASCII)")

// CHECK-NEXT: String(Contiguous(owner: null, count: 11)) = "🏂☃❅❆❄︎⛄️❄️"
// CHECK-NEXT: false
var nonASCIILiteral: String = "🏂☃❅❆❄︎⛄️❄️"
println("  \(repr(nonASCIILiteral))")
println("  \(!asciiLiteral._core.isASCII)")

// ===------- Appending -------===

// These tests are in NewStringAppending.swift.

// ===---------- Comparison --------===

var s = "ABCDEF"
var s1 = s + "G"

// CHECK-NEXT: true
println("\(s) == \(s) => \(s == s)")

// CHECK-NEXT: false
println("\(s) == \(s1) => \(s == s1)")

// CHECK-NEXT: true
let abcdef: String = "ABCDEF"
println("\(s) == \"\(abcdef)\" => \(s == abcdef)")

let so: String = "so"
let sox: String = "sox"
let tocks: String = "tocks"

// CHECK-NEXT: false
println("so < so => \(so < so)")
// CHECK-NEXT: true
println("so < sox => \(so < sox)")
// CHECK-NEXT: true
println("so < tocks => \(so < tocks)")
// CHECK-NEXT: true
println("sox < tocks => \(sox < tocks)")

let qqq = nonASCIILiteral.hasPrefix("🏂☃")
let rrr = nonASCIILiteral.hasPrefix("☃")
let zz = (
  nonASCIILiteral.hasPrefix("🏂☃"), nonASCIILiteral.hasPrefix("☃"),
  nonASCIILiteral.hasSuffix("⛄️❄️"), nonASCIILiteral.hasSuffix("☃"))

// CHECK-NEXT: <true, false, true, false>
println("<\(zz.0), \(zz.1), \(zz.2), \(zz.3)>")

// ===---------- Interpolation --------===

// CHECK-NEXT: {{.*}}"interpolated: foobar 🏂☃❅❆❄︎⛄️❄️ 42 3.14 true"
s = "interpolated: \(asciiLiteral) \(nonASCIILiteral) \(42) \(3.14) \(true)"
println("\(repr(s))")

// ===---------- Views --------===

let winter = "🏂☃❅❆❄︎⛄️❄️"
let summer = "school's out!"

func printHexSequence<
  S:SequenceType where S.Generator.Element : IntegerType
>(s: S) {
  print("[")
  var prefix = ""
  for x in s {
    print(prefix);
    print(String(x.toIntMax(), radix: 16))
    prefix = " "
  }
  println("]")
}

// CHECK-NEXT: [f0 9f 8f 82 e2 98 83 e2 9d 85 e2 9d 86 e2 9d 84 ef b8 8e e2 9b 84 ef b8 8f e2 9d 84 ef b8 8f]
printHexSequence(winter.utf8)
// CHECK-NEXT: [d83c dfc2 2603 2745 2746 2744 fe0e 26c4 fe0f 2744 fe0f]
printHexSequence(winter.utf16)
// CHECK-NEXT: [73 63 68 6f 6f 6c 27 73 20 6f 75 74 21]
printHexSequence(summer.utf8)
// CHECK-NEXT: [73 63 68 6f 6f 6c 27 73 20 6f 75 74 21]
printHexSequence(summer.utf16)

func utf8GraphemeClusterIndices(s: String) -> [String.UTF8Index] {
  return indices(s).map { $0.samePositionIn(s.utf8) }
}

func utf8UnicodeScalarIndices(s: String) -> [String.UTF8Index] {
  return indices(s.unicodeScalars).map { $0.samePositionIn(s.utf8) }
}

func utf8UTF16Indices(s: String) -> [String.UTF8Index?] {
  return indices(s.utf16).map { $0.samePositionIn(s.utf8) }
}

// winter UTF8 grapheme clusters ([]) and unicode scalars (|)
// [f0 9f 8f 82] [e2 98 83] [e2 9d 85] [e2 9d 86] [e2 9d 84 | ef b8 8e]
// [e2 9b 84 | ef b8 8f]    [e2 9d 84 | ef b8 8f]

// Print the first four utf8 code units at the start of each grapheme
// cluster
//
// CHECK-NEXT: [f0 9f 8f 82]
// CHECK-NEXT: [e2 98 83 e2]
// CHECK-NEXT: [e2 9d 85 e2]
// CHECK-NEXT: [e2 9d 86 e2]
// CHECK-NEXT: [e2 9d 84 ef]
// CHECK-NEXT: [e2 9b 84 ef]
// CHECK-NEXT: [e2 9d 84 ef]
for i in utf8GraphemeClusterIndices(winter) {
  printHexSequence((0..<4).map { winter.utf8[advance(i, $0)] })
}

// CHECK-NEXT: [73 63 68 6f 6f 6c 27 73 20 6f 75 74 21]
printHexSequence(utf8GraphemeClusterIndices(summer).map { summer.utf8[$0] })

// Print the first three utf8 code units at the start of each unicode
// scalar
//
// CHECK-NEXT: [f0 9f 8f]
// CHECK-NEXT: [e2 98 83]
// CHECK-NEXT: [e2 9d 85]
// CHECK-NEXT: [e2 9d 86]
// CHECK-NEXT: [e2 9d 84]
// CHECK-NEXT: [ef b8 8e]
// CHECK-NEXT: [e2 9b 84]
// CHECK-NEXT: [ef b8 8f]
// CHECK-NEXT: [e2 9d 84]
// CHECK-NEXT: [ef b8 8f]
for i in utf8UnicodeScalarIndices(winter) {
  printHexSequence((0..<3).map { winter.utf8[advance(i, $0)] })
}

// CHECK-NEXT: [73 63 68 6f 6f 6c 27 73 20 6f 75 74 21]
printHexSequence(utf8UnicodeScalarIndices(summer).map { summer.utf8[$0] })

// Print the first three utf8 code units at the start of each utf16
// code unit, or invalid when between code units
//
// CHECK-NEXT: [f0 9f 8f]
// CHECK-NEXT: invalid
// CHECK-NEXT: [e2 98 83]
// CHECK-NEXT: [e2 9d 85]
// CHECK-NEXT: [e2 9d 86]
// CHECK-NEXT: [e2 9d 84]
// CHECK-NEXT: [ef b8 8e]
// CHECK-NEXT: [e2 9b 84]
// CHECK-NEXT: [ef b8 8f]
// CHECK-NEXT: [e2 9d 84]
// CHECK-NEXT: [ef b8 8f]
for i16 in indices(winter.utf16) {
  if let i8 = i16.samePositionIn(winter.utf8) {
    printHexSequence((0..<3).map { winter.utf8[advance(i8, $0)] })
  }
  else {
    println("invalid")
  }
}
// CHECK-NEXT: [73 63 68 6f 6f 6c 27 73 20 6f 75 74 21]
printHexSequence(utf8UTF16Indices(summer).map { summer.utf8[$0!] })

// Make sure that equivalent UTF8 indices computed in different ways
// are still equal.
//
// CHECK-NEXT: true
let abc = "abcdefghijklmnop"
println(
  String.UTF8Index(abc.startIndex, within: abc.utf8).successor()
  == String.UTF8Index(abc.startIndex.successor(), within: abc.utf8))

func expectEquality<T: Equatable>(x: T, y: T, expected: Bool) {
  let actual = x == y
  if expected != actual {
    let op = actual ? "==" : "!="
    println("unexpectedly, \(x) \(op) \(y)")
  }
  if actual != (y == x) {
    println("equality is asymmetric")
  }
}

func expectNil<T>(x: T?) {
  if x != nil { println("unexpected non-nil") }
}
extension String.UTF8View.Index : Printable {
  public var description: String {
    return "[\(_coreIndex):\(hex(_buffer))]"
  }
}

do {
  let diverseCharacters = summer + winter + winter + summer
  let s = diverseCharacters.unicodeScalars
  let u8 = diverseCharacters.utf8
  let u16 = diverseCharacters.utf16
  
  for si0 in indices(s) {
    for (ds, si1) in enumerate(si0..<s.endIndex) {
      
      // Map those unicode scalar indices into utf8 indices
      let u8i1 = si1.samePositionIn(u8)
      let u8i0 = si0.samePositionIn(u8)

      var u8i0a = u8i0 // an index to advance
      var dsa = 0      // count unicode scalars while doing so
      
      // Advance u8i0a to the same unicode scalar as u8i1.  The scalar
      // number will increase each time we move off a scalar's leading
      // byte, so we need to keep going through any continuation bytes
      while (dsa < ds || UTF8.isContinuation(u8[u8i0a])) {
        expectEquality(u8i0a, u8i1, false)
        let b = u8[u8i0a]
        if !UTF8.isContinuation(b) {
          ++dsa
          // On a unicode scalar boundary we should be able to round-trip through UTF16
          let u16i0a = u8i0a.samePositionIn(u16)!
          expectEquality(u8i0a, u16i0a.samePositionIn(u8)!, true)
          if UTF16.isLeadSurrogate(u16[u16i0a]) {
            // utf16 indices of trailing surrogates should not convert to utf8
            expectNil(u16i0a.successor().samePositionIn(u8))
          }
        }
        else {
          // Between unicode scalars we should not be able to convert to UTF16
          expectNil(u8i0a.samePositionIn(u16))
        }
        ++u8i0a
      }
      expectEquality(u8i0a, u8i1, true)

      // Also check some positions between unicode scalars
      for n0 in 0..<8 {
        let u8i0b = advance(u8i0a, n0)
        for n1 in n0..<8 {
          let u8i1b = advance(u8i1, n1)
          expectEquality(u8i0b, u8i1b, n0 == n1)
          if u8i1b == u8.endIndex { break }
        }
        if u8i0b == u8.endIndex { break }
      }
    }
  }
}
while false

// ===---------- Done --------===
// CHECK-NEXT: Done.
println("Done.")

