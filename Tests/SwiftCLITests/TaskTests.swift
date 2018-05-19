//
//  TaskTests.swift
//  SwiftCLITests
//
//  Created by Jake Heiser on 4/1/18.
//

import Foundation
import SwiftCLI
import XCTest

class TaskTests: XCTestCase {
    
    static var allTests : [(String, (TaskTests) -> () throws -> Void)] {
        return [
            ("testRun", testRun),
            ("testCapture", testCapture),
            ("testExecutableFind", testExecutableFind),
            ("testBashRun", testBashRun),
            ("testBashCapture", testBashCapture),
            ("testIn", testIn),
            ("testPipe", testPipe),
            ("testCurrentDirectory", testCurrentDirectory),
            ("testEnv", testEnv),
            ("testSignals", testSignals),
            ("testTaskLineStream", testTaskLineStream)
        ]
    }
    
    func testRun() throws {
        let file = "file.txt"
        try SwiftCLI.run("/usr/bin/touch", file)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: file))
        try FileManager.default.removeItem(atPath: file)
    }
    
    func testCapture() throws {
        let path = "/tmp/_swiftcli"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        FileManager.default.createFile(atPath: path + "/SwiftCLI", contents: nil, attributes: nil)
        defer { try! FileManager.default.removeItem(atPath: path) }
        
        let output = try capture("/bin/ls", path)
        XCTAssertEqual(output.stdout, "SwiftCLI")
        XCTAssertEqual(output.stderr, "")
    }
    
    func testExecutableFind() throws {
        let path = "/tmp/_swiftcli"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        FileManager.default.createFile(atPath: path + "/SwiftCLI", contents: nil, attributes: nil)
        defer { try! FileManager.default.removeItem(atPath: path) }
        
        XCTAssertEqual(Task.findExecutable(named: "ls"), "/bin/ls")
        
        let output = try capture("ls", path)
        XCTAssertEqual(output.stdout, "SwiftCLI")
        XCTAssertEqual(output.stderr, "")
    }
    
    func testBashRun() throws {
        let file = "file.txt"
        try SwiftCLI.run(bash: "touch \(file)")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: file))
        try FileManager.default.removeItem(atPath: file)
    }
    
    func testBashCapture() throws {
        let path = "/tmp/_swiftcli"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        FileManager.default.createFile(atPath: path + "/SwiftCLI", contents: nil, attributes: nil)
        defer { try! FileManager.default.removeItem(atPath: path) }
        
        let output = try capture(bash: "ls \(path)")
        XCTAssertEqual(output.stdout, "SwiftCLI")
        XCTAssertEqual(output.stderr, "")
    }
    
    func testIn() throws {
        let input = PipeStream()
        
        let output = PipeStream()
        let task = Task(executable: "/usr/bin/sort", stdout: output, stdin: input)
        task.runAsync()
        
        input <<< "beta"
        input <<< "alpha"
        input.closeWrite()
        
        let code = task.finish()
        XCTAssertEqual(code, 0)
        XCTAssertEqual(output.readAll(), "alpha\nbeta\n")
    }
    
    func testPipe() throws {
        let path = "/tmp/_swiftcli"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        FileManager.default.createFile(atPath: path + "/Info.plist", contents: nil, attributes: nil)
        FileManager.default.createFile(atPath: path + "/LinuxMain.swift", contents: nil, attributes: nil)
        FileManager.default.createFile(atPath: path + "/SwiftCLITests", contents: nil, attributes: nil)
        defer { try! FileManager.default.removeItem(atPath: path) }
        
        let connector = PipeStream()
        let output = PipeStream()
        
        let ls = Task(executable: "ls", args: [path], stdout: connector)
        let grep = Task(executable: "grep", args: ["Swift"], stdout: output, stdin: connector)
        
        ls.runAsync()
        grep.runAsync()
                
        XCTAssertEqual(output.readAll(), "SwiftCLITests\n")
    }
    
    func testCurrentDirectory() throws {
        let path = "/tmp/_swiftcli"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        FileManager.default.createFile(atPath: path + "/SwiftCLI", contents: nil, attributes: nil)
        defer { try! FileManager.default.removeItem(atPath: path) }
        
        let capture = PipeStream()
        
        let ls = Task(executable: "ls", currentDirectory: path, stdout: capture)
        ls.runSync()
        
        XCTAssertEqual(capture.readAll(), "SwiftCLI\n")
    }
    
    func testEnv() {
        let capture = PipeStream()
        
        let echo = Task(executable: "bash", args: ["-c", "echo $MY_VAR"], stdout: capture)
        echo.env["MY_VAR"] = "aVal"
        echo.runSync()
        
        XCTAssertEqual(capture.readAll(), "aVal\n")
    }
    
    func testSignals() {
        let task = Task(executable: "/bin/sleep", args: ["1"])
        task.runAsync()
        
        XCTAssertTrue(task.suspend())
        sleep(2)
        XCTAssertTrue(task.isRunning)
        XCTAssertTrue(task.resume())
        sleep(2)
        XCTAssertFalse(task.isRunning)
        
        // Travis errors when calling interrupt on Linux for unknown reason
        #if os(macOS)
        let task2 = Task(executable: "/bin/sleep", args: ["3"])
        task2.runAsync()
        task2.interrupt()
        XCTAssertEqual(task2.finish(), 2)
        #endif
        
        let task3 = Task(executable: "/bin/sleep", args: ["3"])
        task3.runAsync()
        task3.terminate()
        XCTAssertEqual(task3.finish(), 15)
    }
    
    func testTaskLineStream() throws {
        let path = "/tmp/_swiftcli"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
        FileManager.default.createFile(atPath: path + "/Info.plist", contents: nil, attributes: nil)
        FileManager.default.createFile(atPath: path + "/LinuxMain.swift", contents: nil, attributes: nil)
        FileManager.default.createFile(atPath: path + "/SwiftCLITests", contents: nil, attributes: nil)
        defer { try! FileManager.default.removeItem(atPath: path) }
        
        var count = 0
        let lineStream = LineStream { (line) in
            count += 1
        }
        let task = Task(executable: "ls", args: [path], stdout: lineStream)
        XCTAssertEqual(task.runSync(), 0)
        
        lineStream.wait()
        XCTAssertEqual(count, 3)
    }
    
}