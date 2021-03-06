import Quick
import Nimble
import PathKit
import SourceKittenFramework
@testable import Sourcery

private func build(_ source: String) -> [String: SourceKitRepresentable]? {
    return Structure(file: File(contents: source)).dictionary
}

class FileParserVariableSpec: QuickSpec {
    // swiftlint:disable function_body_length
    override func spec() {
        describe("Parser") {
            describe("parseVariable") {
                func parse(_ code: String) -> Variable? {
                    guard let parser = try? FileParser(contents: code) else { fail(); return nil }
                    let code = build(code)
                    guard let substructures = code?[SwiftDocKey.substructure.rawValue] as? [SourceKitRepresentable],
                          let src = substructures.first as? [String: SourceKitRepresentable] else {
                        fail()
                        return nil
                    }
                    _ = parser.parse()
                    return parser.parseVariable(src, containedInProtocol: false)
                }

                it("ignores private variables") {
                    expect(parse("private var name: String")).to(beNil())
                    expect(parse("fileprivate var name: String")).to(beNil())
                }

                it("extracts standard property correctly") {
                    expect(parse("var name: String")).to(equal(Variable(name: "name", typeName: TypeName("String"), accessLevel: (read: .internal, write: .internal), isComputed: false)))
                }

                context("given variable with initial value") {
                    it("extracts property with default initializer correctly") {
                        expect(parse("var name = String()")?.typeName).to(equal(TypeName("String")))
                        expect(parse("var name = Parent.Children.init()")?.typeName).to(equal(TypeName("Parent.Children")))
                        expect(parse("var name: String? = String()")?.typeName).to(equal(TypeName("String?")))
                    }

                    it("extracts property with literal value correctrly") {
                        expect(parse("var name = 1")?.typeName).to(equal(TypeName("Int")))
                        expect(parse("var name = 1.0")?.typeName).to(equal(TypeName("Double")))
                        expect(parse("var name = \"1\"")?.typeName).to(equal(TypeName("String")))
                        expect(parse("var name = true")?.typeName).to(equal(TypeName("Bool")))
                        expect(parse("var name = false")?.typeName).to(equal(TypeName("Bool")))
                        expect(parse("var name = nil")?.typeName).to(equal(TypeName("Optional")))
                        expect(parse("var name = Optional.none")?.typeName).to(equal(TypeName("<<unknown type, please add type attribution to variable 'var name = Optional.none'>>")))
                        expect(parse("var name = Optional.some(1)")?.typeName).to(equal(TypeName("<<unknown type, please add type attribution to variable 'var name = Optional.some(1)'>>")))
                    }

                    it("extracts property with array literal value correctly") {
                        expect(parse("var name = [Int]()")?.typeName).to(equal(TypeName("[Int]")))
                        expect(parse("var name = [1]")?.typeName).to(equal(TypeName("[Int]")))
                        expect(parse("var name = [1, 2]")?.typeName).to(equal(TypeName("[Int]")))
                        expect(parse("var name = [1, \"a\"]")?.typeName).to(equal(TypeName("[Any]")))
                        expect(parse("var name = [1, nil]")?.typeName).to(equal(TypeName("[Int?]")))
                        expect(parse("var name = [1, [1, 2]]")?.typeName).to(equal(TypeName("[Any]")))
                        expect(parse("var name = [[1, 2], [1, 2]]")?.typeName).to(equal(TypeName("[[Int]]")))
                        expect(parse("var name = [Int()]")?.typeName).to(equal(TypeName("[Int]")))
                    }

                    it("extracts property with dictionary literal value correctly") {
                        expect(parse("var name = [Int: Int]()")?.typeName).to(equal(TypeName("[Int: Int]")))
                        expect(parse("var name = [1: 2]")?.typeName).to(equal(TypeName("[Int: Int]")))
                        expect(parse("var name = [1: 2, 2: 3]")?.typeName).to(equal(TypeName("[Int: Int]")))
                        expect(parse("var name = [1: 1, 2: \"a\"]")?.typeName).to(equal(TypeName("[Int: Any]")))
                        expect(parse("var name = [1: 1, 2: nil]")?.typeName).to(equal(TypeName("[Int: Int?]")))
                        expect(parse("var name = [1: 1, 2: [1, 2]]")?.typeName).to(equal(TypeName("[Int: Any]")))
                        expect(parse("var name = [[1: 1, 2: 2], [1: 1, 2: 2]]")?.typeName).to(equal(TypeName("[[Int: Int]]")))
                        expect(parse("var name = [1: [1: 1, 2: 2], 2: [1: 1, 2: 2]]")?.typeName).to(equal(TypeName("[Int: [Int: Int]]")))
                        expect(parse("var name = [Int(): String()]")?.typeName).to(equal(TypeName("[Int: String]")))
                    }

                    it("extracts property with tuple literal value correctly") {
                        expect(parse("var name = (1, 2)")?.typeName).to(equal(TypeName("(Int, Int)")))
                        expect(parse("var name = (1, b: \"[2,3]\", c: 1)")?.typeName).to(equal(TypeName("(Int, b: String, c: Int)")))
                        expect(parse("var name = (_: 1, b: 2)")?.typeName).to(equal(TypeName("(Int, b: Int)")))
                        expect(parse("var name = ((1, 2), [\"a\": \"b\"])")?.typeName).to(equal(TypeName("((Int, Int), [String: String])")))
                        expect(parse("var name = ((1, 2), [1, 2])")?.typeName).to(equal(TypeName("((Int, Int), [Int])")))
                        expect(parse("var name = ((1, 2), [\"a,b\": \"b\"])")?.typeName).to(equal(TypeName("((Int, Int), [String: String])")))
                    }
                }

                it("extracts standard let property correctly") {
                    let r = parse("let name: String")
                    expect(r).to(equal(Variable(name: "name", typeName: TypeName("String"), accessLevel: (read: .internal, write: .none), isComputed: false)))
                }

                it("extracts computed property correctly") {
                    expect(parse("var name: Int { return 2 }")).to(equal(Variable(name: "name", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true)))
                }

                it("extracts generic property correctly") {
                    expect(parse("let name: Observable<Int>")).to(equal(Variable(name: "name", typeName: TypeName("Observable<Int>"), accessLevel: (read: .internal, write: .none), isComputed: false)))
                }

                it("extracts property with didSet correctly") {
                    expect(parse(
                            "var name: Int? {\n" +
                                    "didSet { _ = 2 }\n" +
                                    "willSet { _ = 4 }\n" +
                                    "}")).to(equal(Variable(name: "name", typeName: TypeName("Int?"), accessLevel: (read: .internal, write: .internal), isComputed: false)))
                }

                context("given it has sourcery annotations") {

                    it("extracts single annotation") {
                        let expectedVariable = Variable(name: "name", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["skipEquability"] = NSNumber(value: true)

                        expect(parse("// sourcery: skipEquability\n" +
                                             "var name: Int { return 2 }")).to(equal(expectedVariable))
                    }

                    it("extracts multiple annotations on the same line") {
                        let expectedVariable = Variable(name: "name", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["skipEquability"] = NSNumber(value: true)
                        expectedVariable.annotations["jsonKey"] = "json_key" as NSString

                        expect(parse("// sourcery: skipEquability, jsonKey = \"json_key\"\n" +
                                             "var name: Int { return 2 }")).to(equal(expectedVariable))
                    }

                    it("extracts multi-line annotations, including numbers") {
                        let expectedVariable = Variable(name: "name", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["skipEquability"] = NSNumber(value: true)
                        expectedVariable.annotations["jsonKey"] = "json_key" as NSString
                        expectedVariable.annotations["thirdProperty"] = NSNumber(value: -3)

                        let result = parse(        "// sourcery: skipEquability, jsonKey = \"json_key\"\n" +
                                                           "// sourcery: thirdProperty = -3\n" +
                                                           "var name: Int { return 2 }")
                        expect(result).to(equal(expectedVariable))
                    }

                    it("extracts annotations interleaved with comments") {
                        let expectedVariable = Variable(name: "name", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["isSet"] = NSNumber(value: true)
                        expectedVariable.annotations["numberOfIterations"] = NSNumber(value: 2)

                        let result = parse(        "// sourcery: isSet\n" +
                                                           "/// isSet is used for something useful\n" +
                                                           "// sourcery: numberOfIterations = 2\n" +
                                                           "var name: Int { return 2 }")
                        expect(result).to(equal(expectedVariable))
                    }

                    it("stops extracting annotations if it encounters a non-comment line") {
                        let expectedVariable = Variable(name: "name", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["numberOfIterations"] = NSNumber(value: 2)

                        let result = parse(        "// sourcery: isSet\n" +
                                                           "\n" +
                                                           "// sourcery: numberOfIterations = 2\n" +
                                                           "var name: Int { return 2 }")
                        expect(result).to(equal(expectedVariable))
                    }
                }
            }
        }
    }
}
