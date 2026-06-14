import ArgumentParser
import Foundation
import Swisp

struct SwispCLI: ParsableCommand {
    @Argument(help: "The Lisp file to evaluate. Use '-' for stdin.")
    var file: String?

    @Flag(name: .long, help: "Skip loading init.lisp at startup")
    var noInit: Bool = false

    @Flag(name: .long, help: "Start an interactive REPL")
    var repl: Bool = false

    mutating func run() throws {
        let env = makeGlobalEnvironment()

        // Load init.lisp from bundle or working directory
        if !noInit {
            if let initPath = resourcePath(for: "init") {
                let initContent = try String(contentsOfFile: initPath, encoding: .utf8)
                var initTokenizer = Tokenizer(input: initContent)
                let initTokens = try initTokenizer.tokenize()
                var initParser = Parser(tokens: initTokens)
                let initExprs = try initParser.parseAll()
                _ = evalAll(initExprs, env: env)
            }
        }

        if repl {
            runREPL(env: env)
            return
        }

        // Load user code
        let content: String
        if let path = file, path != "-" {
            content = try String(contentsOfFile: path, encoding: .utf8)
        } else {
            if let data = try? FileHandle.standardInput.readToEnd() {
                content = String(data: data, encoding: .utf8) ?? ""
            } else {
                content = ""
            }
        }

        // Set up a reader for stream-based reading (enables (read) builtin)
        let reader = Reader(input: content)
        currentReader = reader

        // Read and evaluate one expression at a time
        while !reader.isEOF {
            reader.skipWhitespaceAndComments()
            if reader.isEOF { break }
            do {
                if let expr = try readOne() {
                    let step = eval(expr, env) { val in .done(val) }
                    let result = try trampoline(step)
                    print(result)
                }
            } catch {
                print("Error: \(error)")
                break
            }
        }
    }
}

// MARK: - REPL

func runREPL(env: Frame) {
    signal(SIGINT, SIG_IGN)
    print("Swisp REPL. Use (exit) or Ctrl-D to quit.")
    var buffer = ""
    let isTTY = isatty(STDIN_FILENO) != 0

    while true {
        if isTTY { print("> ", terminator: ""); fflush(stdout) }

        guard let line = readLine() else {
            if isTTY { print() }
            break
        }
        if line == "(exit)" { break }
        if line == "(quit)" { break }

        buffer += line + "\n"

        do {
            var tokenizer = Tokenizer(input: buffer)
            let tokens = try tokenizer.tokenize()
            var parser = Parser(tokens: tokens)
            let exprs = try parser.parseAll()
            for expr in exprs {
                let step = eval(expr, env) { val in .done(val) }
                let result = try trampoline(step)
                print(result)
            }
            buffer = ""
        } catch let error as ParserError {
            if case .unexpectedEOF = error {
                // Incomplete expression — keep reading
                continue
            }
            print("Error: \(error)")
            buffer = ""
        } catch let error as TokenizerError {
            print("Error: \(error)")
            buffer = ""
        } catch {
            print("Error: \(error)")
            buffer = ""
        }
    }
}

SwispCLI.main()
