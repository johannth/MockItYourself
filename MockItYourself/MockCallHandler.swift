//
//  CallHandler.swift
//  QuizUp
//
//  Created by Alex Verein on 03/03/16.
//  Copyright © 2016 Plain Vanilla Games. All rights reserved.
//

public class MockCallHandler {
    private var recordedCalls = [String: CallHistory]()

    private var stubs = [String: StubRegistry]()
    
    private var shouldCheckArgumentsForStub: Bool?
    private var isStubbingMethodCallValue: Stub? = nil
    private var isCapturingMethodCall = false

    private var lastMethodCallName = ""

    public init() {}
    
    private func captureMethodCall(captureBlock: () -> ()) throws -> String {
        isCapturingMethodCall = true
        captureBlock()
        // The above block will contain a call to the method that is being mocked.
        // registerCall will set isCapturingMethodCall to false
        // and set lastCalledMethodName
        if isCapturingMethodCall {
            throw MockVerificationError.MethodNotMocked
        }
        
        let methodCallName = lastMethodCallName
        lastMethodCallName = ""

        return methodCallName
    }

    public func registerCall(methodName: String = #function) {
        registerCall(args: Args0(), methodName: methodName)
    }
    
    public func registerCall<A: Equatable>(args args: A, methodName: String = #function) {
        recordCall(methodName: methodName, args: args)
    }
    
    public func registerCall<R: Any>(defaultReturnValue defaultReturnValue: R?, methodName: String = #function) -> R? {
        return registerCall(args: Args0(), defaultReturnValue: defaultReturnValue, methodName: methodName)
    }
    
    public func registerCall<A: Equatable, R: Any>(args args: A, defaultReturnValue: R?, methodName: String = #function) -> R? {
        recordCall(methodName: methodName, args: args)
        
        if let stubbedValue = isStubbingMethodCallValue, checkArguments = shouldCheckArgumentsForStub {
            recordStub(methodName: methodName, args: args, stubbedValue: stubbedValue, checkArguments: checkArguments)
            
            shouldCheckArgumentsForStub = nil
            isStubbingMethodCallValue = nil
        }
        
        if let recordedStubs = stubs[methodName] as? StubRegistryRecorder<A>, stub = recordedStubs.getStubbedValue(args) {
            switch stub {
            case .Value(let stubbedValue):
                return stubbedValue as? R
            case .Nil:
                return nil
            }
        } else {
            return defaultReturnValue
        }
    }

    public func registerCall<R: Any>(defaultReturnValue defaultReturnValue: R, methodName: String = #function) -> R {
        return registerCall(args: Args0(), defaultReturnValue: defaultReturnValue, methodName: methodName)
    }

    public func registerCall<A: Equatable, R: Any>(args args: A, defaultReturnValue: R, methodName: String = #function) -> R {
        recordCall(methodName: methodName, args: args)
        
        if let stubbedValue = isStubbingMethodCallValue, checkArguments = shouldCheckArgumentsForStub {
            recordStub(methodName: methodName, args: args, stubbedValue: stubbedValue, checkArguments: checkArguments)
            
            shouldCheckArgumentsForStub = nil
            isStubbingMethodCallValue = nil
        }
        
        if let recordedStubs = stubs[methodName] as? StubRegistryRecorder<A>, stub = recordedStubs.getStubbedValue(args) {
            switch stub {
            case .Value(let stubbedValue):
                return stubbedValue as! R
            case .Nil:
                // This case actually doesn't make sense. 
                // It might make sense to throw an exception here
                return defaultReturnValue
            }
        } else {
            return defaultReturnValue
        }
    }
    
    func recordCall<A: Equatable>(methodName methodName: String, args: A) {
        lastMethodCallName = methodName
        
        if let callHistory = recordedCalls[methodName] as? CallHistoryRecorder<A> {
            callHistory.record(args, verificationCall: isCapturingMethodCall)
        } else {
            recordedCalls[methodName] = CallHistoryRecorder(firstArgs: args,
                                                            verificationCall: isCapturingMethodCall)
        }
        
        isCapturingMethodCall = false
    }
    
    func recordStub<A: Equatable>(methodName methodName: String, args: A, stubbedValue: Stub, checkArguments: Bool) {
        if let stubRecorder = stubs[methodName] as? StubRegistryRecorder<A> {
            stubRecorder.stub(args: args, stubbedValue: stubbedValue)
        } else {
            stubs[methodName] = StubRegistryRecorder(args: args, stubbedValue: stubbedValue, checkArguments: checkArguments)
        }
    }

    func verify(expectedCallCount expectedCallCount: Int? = nil, checkArguments: Bool = false, method: () -> ()) throws {
        let methodName = try captureMethodCall(method)
        
        if let callHistory = recordedCalls[methodName] {
            if let expectedCallCount = expectedCallCount {
                let actualCallCount = callHistory.count ?? 0
                if expectedCallCount != actualCallCount {
                    throw MockVerificationError.MethodCallCountMismatch(actualCallCount, expectedCallCount)
                }
            }
            
            if checkArguments {
                let matchFound = callHistory.match(checkAll: expectedCallCount != nil)
                if matchFound == false {
                    if callHistory.count == 0 {
                        throw MockVerificationError.MethodNotCalled
                    } else {
                        throw MockVerificationError.ArgumentsMismatch()
                    }
                    
                }
            }
        } else {
            throw MockVerificationError.MethodNotCalled
        }
    }
    
    func reject(method: () -> ()) throws {
        do {
            try verify(expectedCallCount: 0, method: method)
        } catch {
            throw MockVerificationError.MethodWasCalled
        }
    }
    
    func stub(method: () -> (), andReturnValue returnValue: Any?, checkArguments: Bool = true) throws {
        shouldCheckArgumentsForStub = checkArguments
        isStubbingMethodCallValue = Stub.wrap(returnValue)
        
        let methodName = try captureMethodCall(method)
        
        if let recordedStubs = stubs[methodName] {
            if recordedStubs.checkArguments == false && checkArguments == true {
                throw MockVerificationError.MethodHasBeenStubbedForAllArguments
            }
        }
    }
}

protocol CallHistory {
    var count: Int { get }
    func match(checkAll checkAll: Bool) -> Bool
}

class CallHistoryRecorder<A: Equatable> : CallHistory {
    var history: [A]
    var verificationCall: A?
    
    var count: Int {
        return history.count
    }
    
    init(firstArgs: A, verificationCall: Bool) {
        history = []
        
        record(firstArgs, verificationCall: verificationCall)
    }
    
    func record(args: A, verificationCall: Bool) {
        if verificationCall {
            self.verificationCall = args
        } else {
            history.append(args)
        }
    }
    
    func match(checkAll checkAll: Bool = false) -> Bool {
        if let callToLookFor = verificationCall {
            if checkAll {
                return history.map({ $0 == callToLookFor }).contains(false) == false
            } else {
                return history.contains { $0 == callToLookFor }
            }
        } else {
            return false
        }
    }
}

// We need this type to be able to differentiate between a method
// that hasn't been stubbed and a method that has been stubbed to return nil
enum Stub {
    case Value(Any)
    case Nil
    
    static func wrap(value: Any?) -> Stub {
        if let value = value {
            return Stub.Value(value)
        } else {
            return Stub.Nil
        }
    }
}

protocol StubRegistry {
    var checkArguments: Bool { get }
}

class StubRegistryRecorder<A: Equatable>: StubRegistry {
    var stubs: [(A, Stub)]
    let checkArguments: Bool
    
    init(args: A, stubbedValue: Stub, checkArguments: Bool) {
        stubs = []
        self.checkArguments = checkArguments
        
        stub(args: args, stubbedValue: stubbedValue)
    }
    
    func stub(args args: A, stubbedValue: Stub) {
        if checkArguments == false && stubs.count >= 1 {
            return
        }
        
        removePreviousStubForArgsIfAny(args)
        
        stubs.append((args, stubbedValue))
    }
    
    func removePreviousStubForArgsIfAny(args: A) {
        if getStubbedValue(args) != nil {
            let indexOfPreviousStub = stubs.indexOf({ (argsI, stubI) in
                return argsI == args
            })
            
            if let indexOfPreviousStub = indexOfPreviousStub {
                stubs.removeAtIndex(indexOfPreviousStub)
            }
        }
    }
    
    func getStubbedValue(args: A) -> Stub? {
        let x = stubs.filter({ checkArguments == false || $0.0 == args }).map({ $0.1 }).first
        return x ?? nil
    }
}

enum MockVerificationError: ErrorType {
    case MethodNotCalled
    case MethodWasCalled
    case MethodCallCountMismatch(Int, Int)
    case ArgumentsMismatch()
    case MethodNotMocked
    case MethodHasBeenStubbedForAllArguments
}
