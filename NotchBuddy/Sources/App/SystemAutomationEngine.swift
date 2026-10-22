import AppKit
import Foundation

// MARK: - System & Browser Automation Engine for Cruno (Phase 1)

@MainActor
final class SystemAutomationEngine {
    static let shared = SystemAutomationEngine()

    private init() {}

    // MARK: - Tool Definitions (OpenAI / OpenRouter format)

    static let openAIToolDefinitions: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "open_url",
                "description": "Opens a website or URL in Google Chrome (default) or another specified browser.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "url": [
                            "type": "string",
                            "description": "The full URL to open (e.g. https://github.com or https://google.com)"
                        ],
                        "browser": [
                            "type": "string",
                            "description": "Browser name: 'Google Chrome' (default), 'Safari', 'Arc', or 'default'"
                        ]
                    ],
                    "required": ["url"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "search_web_browser",
                "description": "Performs a web search in Google Chrome (Google, YouTube, GitHub, etc.).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search query terms"
                        ],
                        "engine": [
                            "type": "string",
                            "description": "Search engine: 'google' (default), 'youtube', 'github', 'duckduckgo'"
                        ]
                    ],
                    "required": ["query"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "get_active_browser_tab",
                "description": "Reads the title, URL, and page text content of the currently active tab in Google Chrome or Safari.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "browser": [
                            "type": "string",
                            "description": "Browser name: 'Google Chrome' (default) or 'Safari'"
                        ]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "list_browser_tabs",
                "description": "Lists all open tabs (titles and URLs) currently open in Google Chrome.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "browser": [
                            "type": "string",
                            "description": "Browser name: 'Google Chrome' (default)"
                        ]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "run_chrome_javascript",
                "description": "Executes JavaScript in the active Google Chrome tab to read or manipulate the page.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "script": [
                            "type": "string",
                            "description": "JavaScript code to execute in the front Chrome tab (e.g. document.title, window.location.href)"
                        ]
                    ],
                    "required": ["script"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "open_app",
                "description": "Launches or switches to any application on the user's Mac (e.g. Google Chrome, VS Code, Slack, Spotify, Terminal, Finder, Notes).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "app_name": [
                            "type": "string",
                            "description": "The exact or common name of the application"
                        ]
                    ],
                    "required": ["app_name"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "list_running_apps",
                "description": "Returns a list of all currently active applications running on the Mac.",
                "parameters": [
                    "type": "object",
                    "properties": [:]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "quit_app",
                "description": "Quits or terminates a running application on the Mac.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "app_name": [
                            "type": "string",
                            "description": "The name of the application to quit"
                        ]
                    ],
                    "required": ["app_name"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "manage_clipboard",
                "description": "Reads or copies text to the macOS system clipboard.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "action": [
                            "type": "string",
                            "description": "'get' to read clipboard text, or 'set' to copy text to clipboard"
                        ],
                        "text": [
                            "type": "string",
                            "description": "The text to copy when action is 'set'"
                        ]
                    ],
                    "required": ["action"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "system_volume",
                "description": "Controls the Mac system audio volume or mute state.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "volume_percent": [
                            "type": "integer",
                            "description": "Volume percentage from 0 to 100"
                        ],
                        "mute": [
                            "type": "boolean",
                            "description": "True to mute, false to unmute"
                        ]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "finder_action",
                "description": "Interacts with Finder: open folder, reveal file, or list recent Downloads.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "action": [
                            "type": "string",
                            "description": "'open' to open path, 'reveal' to highlight file in Finder, 'recent_downloads' to see latest downloads"
                        ],
                        "path": [
                            "type": "string",
                            "description": "File or folder path on macOS"
                        ]
                    ],
                    "required": ["action"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "run_applescript",
                "description": "Executes arbitrary AppleScript for deep macOS control (controlling Apple Music, Spotify, Notes, Reminders, Calendar, Finder, etc.).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "script": [
                            "type": "string",
                            "description": "The AppleScript code to run"
                        ]
                    ],
                    "required": ["script"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "run_shell_command",
                "description": "Runs a safe terminal command via zsh (e.g. ls, git status, cat, defaults read, etc.).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description": "The shell command to execute"
                        ]
                    ],
                    "required": ["command"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "take_screenshot",
                "description": "Takes a screenshot of the user's screen or the frontmost application window to visually inspect UI, errors, or elements.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "target": [
                            "type": "string",
                            "description": "'screen' for entire main display, or 'window' for active frontmost app window (default: 'screen')"
                        ]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "mouse_click",
                "description": "Moves mouse cursor to pixel coordinates and clicks. Use this to click buttons, input fields, links, or UI elements on screen.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "x": [
                            "type": "number",
                            "description": "X coordinate in screen pixels"
                        ],
                        "y": [
                            "type": "number",
                            "description": "Y coordinate in screen pixels"
                        ],
                        "button": [
                            "type": "string",
                            "description": "'left' (default), 'right', or 'double'"
                        ]
                    ],
                    "required": ["x", "y"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "mouse_move",
                "description": "Moves the mouse cursor to a specific screen coordinate without clicking.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "x": [
                            "type": "number",
                            "description": "X coordinate in screen pixels"
                        ],
                        "y": [
                            "type": "number",
                            "description": "Y coordinate in screen pixels"
                        ]
                    ],
                    "required": ["x", "y"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "type_text",
                "description": "Types text directly into the currently focused input field or text area on the user's Mac.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "The exact text to type"
                        ]
                    ],
                    "required": ["text"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "press_key",
                "description": "Presses a keyboard key or hotkey (e.g. Return, Tab, Escape, Backspace, Space, or shortcuts like Cmd+C, Cmd+V).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "key": [
                            "type": "string",
                            "description": "The key name: 'return', 'tab', 'escape', 'space', 'delete', 'up', 'down', 'left', 'right', 'c', 'v', 'a', etc."
                        ],
                        "modifiers": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Optional modifiers: ['cmd'], ['shift'], ['alt'], ['ctrl']"
                        ]
                    ],
                    "required": ["key"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "scroll_screen",
                "description": "Scrolls the active window up or down.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "direction": [
                            "type": "string",
                            "description": "'up' or 'down'"
                        ],
                        "amount": [
                            "type": "integer",
                            "description": "Number of scroll lines (default: 5)"
                        ]
                    ],
                    "required": ["direction"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "deep_web_search",
                "description": "Performs an in-depth web search with authoritative source citations, extracting live web snippets and facts without opening a browser.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The search query (e.g. latest news, documentation, facts, current events)"
                        ],
                        "max_results": [
                            "type": "integer",
                            "description": "Maximum number of source results (default: 4)"
                        ]
                    ],
                    "required": ["query"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "search_local_files",
                "description": "Searches for files and documents on the Mac instantly using Spotlight metadata (searches file names and full text contents).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Keywords, filenames, or content to search for"
                        ],
                        "folder": [
                            "type": "string",
                            "description": "Optional search folder: 'Downloads', 'Documents', 'Desktop', or directory path"
                        ]
                    ],
                    "required": ["query"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "read_local_file",
                "description": "Reads and extracts text from any file on the Mac (supports code, text, Markdown, JSON, YAML, and PDF documents).",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "The absolute or tilde path to the file (e.g. ~/Downloads/report.pdf, ~/Desktop/notes.txt)"
                        ]
                    ],
                    "required": ["path"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "get_clipboard",
                "description": "Reads the current contents and recent history of the macOS system clipboard.",
                "parameters": [
                    "type": "object",
                    "properties": [:]
                ]
            ]
        ]
    ]

    // MARK: - Tool Definitions (Anthropic Claude format)

    static let anthropicToolDefinitions: [[String: Any]] = openAIToolDefinitions.compactMap { tool in
        guard let fn = tool["function"] as? [String: Any],
              let name = fn["name"] as? String,
              let desc = fn["description"] as? String,
              let params = fn["parameters"] as? [String: Any] else { return nil }
        return [
            "name": name,
            "description": desc,
            "input_schema": params
        ]
    }

    // MARK: - Unified Tool Dispatcher

    func executeTool(name: String, arguments: [String: Any]) async -> String {
        switch name {
        case "open_url":
            let url = arguments["url"] as? String ?? ""
            let browser = arguments["browser"] as? String
            return await openURL(url, browser: browser)

        case "search_web_browser":
            let query = arguments["query"] as? String ?? ""
            let engine = arguments["engine"] as? String ?? "google"
            return await searchWebInBrowser(query: query, engine: engine)

        case "get_active_browser_tab":
            let browser = arguments["browser"] as? String ?? "Google Chrome"
            return await getActiveBrowserTab(browser: browser)

        case "list_browser_tabs":
            let browser = arguments["browser"] as? String ?? "Google Chrome"
            return await listBrowserTabs(browser: browser)

        case "run_chrome_javascript":
            let script = arguments["script"] as? String ?? ""
            return await runChromeJavaScript(script: script)

        case "open_app":
            let appName = arguments["app_name"] as? String ?? ""
            return await openApp(appName: appName)

        case "list_running_apps":
            return listRunningApps()

        case "quit_app":
            let appName = arguments["app_name"] as? String ?? ""
            return quitApp(appName: appName)

        case "manage_clipboard":
            let action = arguments["action"] as? String ?? "get"
            let text = arguments["text"] as? String ?? ""
            if action == "set" {
                return setClipboard(text: text)
            } else {
                return getClipboard()
            }

        case "system_volume":
            let percent = arguments["volume_percent"] as? Int
            let mute = arguments["mute"] as? Bool
            return setSystemVolume(percent: percent, mute: mute)

        case "finder_action":
            let action = arguments["action"] as? String ?? "recent_downloads"
            let path = arguments["path"] as? String ?? ""
            return await handleFinderAction(action: action, path: path)

        case "run_applescript":
            let script = arguments["script"] as? String ?? ""
            return runAppleScript(script)

        case "run_shell_command":
            let command = arguments["command"] as? String ?? ""
            return await runShell(command: command)

        case "take_screenshot":
            let target = arguments["target"] as? String ?? "screen"
            let capture = target == "window"
                ? await ScreenCaptureEngine.shared.captureFrontmostWindow()
                : await ScreenCaptureEngine.shared.captureMainScreen()
            if let cap = capture {
                return "Screenshot captured successfully (\(Int(cap.image.size.width))x\(Int(cap.image.size.height))). Image base64 data length: \(cap.base64.count) chars."
            } else {
                return "Failed to capture screenshot. Check Screen Recording permissions in System Settings."
            }

        case "mouse_click":
            let x = CGFloat(arguments["x"] as? Double ?? Double(arguments["x"] as? Int ?? 0))
            let y = CGFloat(arguments["y"] as? Double ?? Double(arguments["y"] as? Int ?? 0))
            let btn = arguments["button"] as? String ?? "left"
            let count = btn == "double" ? 2 : 1
            let buttonName = btn == "double" ? "left" : btn
            return MouseKeyboardSimulator.shared.click(at: CGPoint(x: x, y: y), button: buttonName, count: count)

        case "mouse_move":
            let x = CGFloat(arguments["x"] as? Double ?? Double(arguments["x"] as? Int ?? 0))
            let y = CGFloat(arguments["y"] as? Double ?? Double(arguments["y"] as? Int ?? 0))
            return MouseKeyboardSimulator.shared.move(to: CGPoint(x: x, y: y))

        case "type_text":
            let text = arguments["text"] as? String ?? ""
            return MouseKeyboardSimulator.shared.typeText(text)

        case "press_key":
            let key = arguments["key"] as? String ?? "return"
            let mods = arguments["modifiers"] as? [String] ?? []
            return MouseKeyboardSimulator.shared.pressKey(key: key, modifiers: mods)

        case "scroll_screen":
            let dir = arguments["direction"] as? String ?? "down"
            let amt = arguments["amount"] as? Int ?? 5
            return MouseKeyboardSimulator.shared.scroll(direction: dir, amount: amt)

        case "deep_web_search":
            let query = arguments["query"] as? String ?? ""
            let maxResults = arguments["max_results"] as? Int ?? 4
            let result = await WebResearchEngine.shared.search(query: query, maxResults: maxResults)
            return result.summaryText

        case "search_local_files":
            let query = arguments["query"] as? String ?? ""
            let folder = arguments["folder"] as? String
            let items = await LocalFileSearchEngine.shared.searchFiles(query: query, scope: folder)
            if items.isEmpty { return "No matching files found for '\(query)'." }
            var out = "Found \(items.count) matching file(s):\n"
            for (idx, it) in items.enumerated() {
                out += "[\(idx + 1)] \(it.name) (\(it.formattedSize)) - \(it.path)\n"
            }
            return out

        case "read_local_file":
            let path = arguments["path"] as? String ?? ""
            return await LocalFileSearchEngine.shared.readFileContent(path: path)

        case "get_clipboard":
            return LocalFileSearchEngine.shared.getClipboardContent()

        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Action Summary Formatter (for Chat Visual Banners)

    static func formatActionSummary(name: String, arguments: [String: Any]) -> String {
        switch name {
        case "open_url":
            let url = arguments["url"] as? String ?? ""
            return "Opened \(url)"
        case "search_web_browser":
            let q = arguments["query"] as? String ?? ""
            let engine = (arguments["engine"] as? String ?? "Google").capitalized
            return "Searched \(engine): \"\(q)\""
        case "open_app":
            let app = arguments["app_name"] as? String ?? ""
            return "Activated \(app)"
        case "quit_app":
            let app = arguments["app_name"] as? String ?? ""
            return "Quit \(app)"
        case "manage_clipboard":
            let action = arguments["action"] as? String ?? ""
            return action == "set" ? "Copied text to clipboard" : "Read clipboard"
        case "system_volume":
            if let p = arguments["volume_percent"] as? Int {
                return "Set system volume to \(p)%"
            } else if let m = arguments["mute"] as? Bool {
                return m ? "Muted system audio" : "Unmuted system audio"
            }
            return "Adjusted system volume"
        case "finder_action":
            let action = arguments["action"] as? String ?? ""
            return action == "recent_downloads" ? "Checked recent downloads" : "Finder: \(action)"
        case "run_shell_command":
            let cmd = arguments["command"] as? String ?? ""
            return "Executed command: \(cmd)"
        case "run_applescript":
            return "Executed AppleScript"
        case "take_screenshot":
            let target = arguments["target"] as? String ?? "screen"
            return "Captured \(target) screenshot"
        case "mouse_click":
            let x = Int(arguments["x"] as? Double ?? Double(arguments["x"] as? Int ?? 0))
            let y = Int(arguments["y"] as? Double ?? Double(arguments["y"] as? Int ?? 0))
            let btn = arguments["button"] as? String ?? "click"
            return "Mouse \(btn) at (\(x), \(y))"
        case "mouse_move":
            let x = Int(arguments["x"] as? Double ?? Double(arguments["x"] as? Int ?? 0))
            let y = Int(arguments["y"] as? Double ?? Double(arguments["y"] as? Int ?? 0))
            return "Moved mouse to (\(x), \(y))"
        case "type_text":
            let t = arguments["text"] as? String ?? ""
            let trunc = t.count > 25 ? String(t.prefix(25)) + "…" : t
            return "Typed \"\(trunc)\""
        case "press_key":
            let k = arguments["key"] as? String ?? ""
            let mods = arguments["modifiers"] as? [String] ?? []
            let modStr = mods.isEmpty ? "" : mods.joined(separator: "+") + "+"
            return "Key: \(modStr)\(k.capitalized)"
        case "scroll_screen":
            let dir = arguments["direction"] as? String ?? "down"
            return "Scrolled \(dir)"
        case "deep_web_search":
            let q = arguments["query"] as? String ?? ""
            return "Researched web: \"\(q)\""
        case "search_local_files":
            let q = arguments["query"] as? String ?? ""
            return "Searched files: \"\(q)\""
        case "read_local_file":
            let p = arguments["path"] as? String ?? ""
            let name = (p as NSString).lastPathComponent
            return "Read \(name)"
        case "get_clipboard":
            return "Read clipboard"
        default:
            return ""
        }
    }

    // MARK: - Browser & Chrome Actions

    func openURL(_ urlString: String, browser: String?) async -> String {
        var cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.lowercased().hasPrefix("http://") && !cleanURL.lowercased().hasPrefix("https://") {
            cleanURL = "https://" + cleanURL
        }
        guard let url = URL(string: cleanURL) else {
            return "Error: Invalid URL '\(urlString)'"
        }

        let targetBrowser = browser?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Google Chrome"
        if targetBrowser.lowercased().contains("chrome") {
            let script = """
            tell application "Google Chrome"
                activate
                if (count of windows) = 0 then
                    make new window
                    set URL of active tab of front window to "\(cleanURL)"
                else
                    make new tab at end of tabs of front window with properties {URL:"\(cleanURL)"}
                end if
            end tell
            """
            let result = runAppleScript(script)
            if !result.hasPrefix("Error") {
                return "Successfully opened '\(cleanURL)' in Google Chrome."
            }
        }

        // Fallback to NSWorkspace open
        if NSWorkspace.shared.open(url) {
            return "Opened '\(cleanURL)' in default browser."
        } else {
            return "Failed to open '\(cleanURL)'."
        }
    }

    func searchWebInBrowser(query: String, engine: String) async -> String {
        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return "Invalid search query."
        }
        let url: String
        switch engine.lowercased() {
        case "youtube":
            url = "https://www.youtube.com/results?search_query=\(escaped)"
        case "github":
            url = "https://github.com/search?q=\(escaped)"
        case "duckduckgo":
            url = "https://duckduckgo.com/?q=\(escaped)"
        default:
            url = "https://www.google.com/search?q=\(escaped)"
        }
        return await openURL(url, browser: "Google Chrome")
    }

    func getActiveBrowserTab(browser: String) async -> String {
        let isChrome = browser.lowercased().contains("chrome")
        let script: String
        if isChrome {
            script = """
            tell application "Google Chrome"
                if (count of windows) = 0 then return "No open windows in Google Chrome"
                set tabTitle to title of active tab of front window
                set tabURL to URL of active tab of front window
                set tabText to ""
                try
                    set tabText to execute front window's active tab javascript "document.body.innerText.substring(0, 3000)"
                end try
                return "Title: " & tabTitle & "\nURL: " & tabURL & "\nContent Snippet:\n" & tabText
            end tell
            """
        } else {
            script = """
            tell application "Safari"
                if (count of windows) = 0 then return "No open windows in Safari"
                set tabTitle to name of current tab of front window
                set tabURL to URL of current tab of front window
                set tabText to ""
                try
                    set tabText to do JavaScript "document.body.innerText.substring(0, 3000)" in current tab of front window
                end try
                return "Title: " & tabTitle & "\nURL: " & tabURL & "\nContent Snippet:\n" & tabText
            end tell
            """
        }
        return runAppleScript(script)
    }

    func listBrowserTabs(browser: String) async -> String {
        let script = """
        tell application "Google Chrome"
            if (count of windows) = 0 then return "No open windows in Google Chrome"
            set tabList to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabList to tabList & (title of t) & " - " & (URL of t) & "\n"
                end repeat
            end repeat
            return tabList
        end tell
        """
        return runAppleScript(script)
    }

    func runChromeJavaScript(script: String) async -> String {
        let escapedScript = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let asScript = """
        tell application "Google Chrome"
            if (count of windows) = 0 then return "Error: Google Chrome has no open windows."
            return execute front window's active tab javascript "\(escapedScript)"
        end tell
        """
        return runAppleScript(asScript)
    }

    // MARK: - Application Control

    func openApp(appName: String) async -> String {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if NSWorkspace.shared.launchApplication(trimmed) {
            return "Successfully launched or activated '\(trimmed)'."
        }
        // Try open -a via shell as backup
        let res = await runShell(command: "open -a \"\(trimmed)\"")
        if res.isEmpty {
            return "Activated '\(trimmed)'."
        }
        return res
    }

    func listRunningApps() -> String {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .sorted()
        return "Running Applications (\(apps.count)):\n" + apps.joined(separator: ", ")
    }

    func quitApp(appName: String) -> String {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.localizedName?.lowercased() == appName.lowercased() }
        guard let app = running.first else {
            return "Application '\(appName)' is not currently running."
        }
        let success = app.terminate()
        return success ? "Requested '\(appName)' to terminate." : "Could not terminate '\(appName)'."
    }

    // MARK: - Clipboard Management

    func getClipboard() -> String {
        if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            let truncated = str.count > 2000 ? String(str.prefix(2000)) + "\n[truncated]" : str
            return "Clipboard content:\n\(truncated)"
        }
        return "Clipboard is empty or contains non-text data."
    }

    func setClipboard(text: String) -> String {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return "Copied to clipboard (\(text.count) characters)."
    }

    // MARK: - System Settings / Audio

    func setSystemVolume(percent: Int?, mute: Bool?) -> String {
        var actions: [String] = []
        if let m = mute {
            let script = "set volume \(m ? "with" : "without") output muted"
            _ = runAppleScript(script)
            actions.append(m ? "muted" : "unmuted")
        }
        if let p = percent {
            let clamped = max(0, min(100, p))
            let script = "set volume output volume \(clamped)"
            _ = runAppleScript(script)
            actions.append("set volume to \(clamped)%")
        }
        return actions.isEmpty ? "No volume changes specified." : "System audio: \(actions.joined(separator: ", "))."
    }

    // MARK: - Finder Actions

    func handleFinderAction(action: String, path: String) async -> String {
        switch action.lowercased() {
        case "open":
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if NSWorkspace.shared.open(url) {
                return "Opened '\(expanded)' in Finder."
            } else {
                return "Failed to open '\(expanded)'."
            }

        case "reveal":
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return "Revealed '\(expanded)' in Finder."

        case "recent_downloads":
            let downloadsPath = ("~/Downloads" as NSString).expandingTildeInPath
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: downloadsPath) else {
                return "Could not read ~/Downloads directory."
            }
            let fileURLs = items.map { URL(fileURLWithPath: downloadsPath).appendingPathComponent($0) }
            let sorted = fileURLs.compactMap { url -> (URL, Date)? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let mod = attrs[.modificationDate] as? Date else { return nil }
                return (url, mod)
            }.sorted { $0.1 > $1.1 }.prefix(10)

            var report = "Recent 10 files in Downloads:\n"
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, HH:mm"
            for (url, date) in sorted {
                report += "- \(url.lastPathComponent) (\(formatter.string(from: date)))\n"
            }
            return report

        default:
            return "Unknown Finder action: \(action)"
        }
    }

    // MARK: - Script & Shell Execution

    func runAppleScript(_ script: String) -> String {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)
        if let err = error {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            return "Error: \(msg)"
        }
        return result?.stringValue ?? "Success"
    }

    func runShell(command: String) async -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Executed (no output)." : trimmed
        } catch {
            return "Error running command: \(error.localizedDescription)"
        }
    }
}
