import Foundation

final class HIDRunLoopThread {
    private let queue = DispatchQueue(label: "com.dxlight.hid.runloop")
    private var runLoopStorage: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)

    var runLoop: CFRunLoop {
        guard let runLoopStorage else {
            fatalError("HID run loop not ready")
        }
        return runLoopStorage
    }

    init() {
        queue.async {
            self.runLoopStorage = CFRunLoopGetCurrent()
            self.started.signal()
            CFRunLoopRun()
        }
        started.wait()
    }

    func perform<T>(_ work: @escaping () throws -> T) throws -> T {
        var output: Result<T, Error>?
        let finished = DispatchSemaphore(value: 0)

        queue.async {
            output = Result { try work() }
            finished.signal()
        }

        finished.wait()
        return try output!.get()
    }

    func performIfRunning(_ work: @escaping () -> Void) {
        let finished = DispatchSemaphore(value: 0)
        queue.async {
            work()
            finished.signal()
        }
        finished.wait()
    }
}
