use chrono::Local;
use crossterm::style::{Color, Print, ResetColor, SetForegroundColor};
use crossterm::{execute, terminal};
use serde_json::Value;
use std::env;
use std::fs::File;
use std::io::{self, BufRead, BufReader, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

const CYAN: Color = Color::Cyan;
const GREEN: Color = Color::Green;
const YELLOW: Color = Color::Yellow;
const RED: Color = Color::Red;
const MAGENTA: Color = Color::Magenta;
const DIM: Color = Color::DarkGrey;
const WHITE: Color = Color::White;
const BLUE: Color = Color::Blue;

fn color_print(color: Color, text: &str) {
    let mut stdout = io::stdout();
    let _ = execute!(stdout, SetForegroundColor(color), Print(text), ResetColor);
}

fn color_println(color: Color, text: &str) {
    color_print(color, text);
    println!();
}

fn truncate(s: &str, max: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= max {
        s.to_string()
    } else {
        let truncated: String = chars[..max].iter().collect();
        format!("{truncated}...")
    }
}

fn format_tool_use(name: &str, input: &Value) -> String {
    match name {
        "Write" | "Edit" => {
            let path = input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            let short = Path::new(path)
                .file_name()
                .map(|f| f.to_string_lossy().to_string())
                .unwrap_or_else(|| path.to_string());
            if name == "Write" {
                let lines = input
                    .get("content")
                    .and_then(|v| v.as_str())
                    .map(|c| c.lines().count())
                    .unwrap_or(0);
                format!("{short} ({lines} lines)")
            } else {
                let old = input
                    .get("old_string")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                format!("{short} ({})", truncate(old, 40))
            }
        }
        "Read" => {
            let path = input
                .get("file_path")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            Path::new(path)
                .file_name()
                .map(|f| f.to_string_lossy().to_string())
                .unwrap_or_else(|| path.to_string())
        }
        "Bash" => {
            let cmd = input
                .get("command")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            truncate(cmd, 60)
        }
        "Glob" => {
            let pat = input
                .get("pattern")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            pat.to_string()
        }
        "Grep" => {
            let pat = input
                .get("pattern")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            truncate(pat, 50)
        }
        "TodoWrite" => "[tasks updated]".to_string(),
        "Agent" => {
            let desc = input
                .get("description")
                .and_then(|v| v.as_str())
                .unwrap_or("?");
            truncate(desc, 50)
        }
        "AskUserQuestion" => "⚠️  ASKING USER (should not happen in loop!)".to_string(),
        _ => {
            let s = serde_json::to_string(input).unwrap_or_default();
            truncate(&s, 60)
        }
    }
}

fn tool_color(name: &str) -> Color {
    match name {
        "Write" => GREEN,
        "Edit" => YELLOW,
        "Read" => CYAN,
        "Bash" => MAGENTA,
        "Glob" | "Grep" => BLUE,
        "Agent" => Color::AnsiValue(208), // orange
        "AskUserQuestion" => RED,
        "TodoWrite" => DIM,
        _ => WHITE,
    }
}

fn process_line(line: &str, stats: &mut Stats) {
    let obj: Value = match serde_json::from_str(line) {
        Ok(v) => v,
        Err(_) => return,
    };

    let msg_type = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");

    match msg_type {
        "assistant" => {
            let content = match obj
                .get("message")
                .and_then(|m| m.get("content"))
                .and_then(|c| c.as_array())
            {
                Some(c) => c,
                None => return,
            };

            for item in content {
                let item_type = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
                match item_type {
                    "tool_use" => {
                        let name = item.get("name").and_then(|v| v.as_str()).unwrap_or("?");
                        let input = item.get("input").unwrap_or(&Value::Null);
                        let detail = format_tool_use(name, input);
                        let color = tool_color(name);

                        stats.tool_calls += 1;
                        *stats.tool_counts.entry(name.to_string()).or_insert(0) += 1;

                        let ts = Local::now().format("%H:%M:%S").to_string();
                        color_print(DIM, &format!("  {ts} "));
                        color_print(color, &format!("{name:<12}"));
                        color_print(DIM, " → ");
                        color_println(WHITE, &detail);
                    }
                    "text" => {
                        let text = item.get("text").and_then(|v| v.as_str()).unwrap_or("");
                        if !text.trim().is_empty() {
                            let trimmed = truncate(text.trim(), 100);
                            let ts = Local::now().format("%H:%M:%S").to_string();
                            color_print(DIM, &format!("  {ts} "));
                            color_print(DIM, "💬           ");
                            color_println(WHITE, &trimmed);
                        }
                    }
                    _ => {}
                }
            }
        }
        "result" => {
            // tool result — only show errors
            let is_error = obj.get("is_error").and_then(|v| v.as_bool()).unwrap_or(false);
            if is_error {
                let result_text = obj
                    .get("result")
                    .and_then(|v| v.as_str())
                    .or_else(|| {
                        obj.get("result")
                            .and_then(|v| v.as_array())
                            .and_then(|arr| arr.first())
                            .and_then(|v| v.get("text"))
                            .and_then(|v| v.as_str())
                    })
                    .unwrap_or("unknown error");
                let ts = Local::now().format("%H:%M:%S").to_string();
                color_print(DIM, &format!("  {ts} "));
                color_print(RED, "❌ ERROR     ");
                color_println(RED, &truncate(result_text, 80));
                stats.errors += 1;
            }
        }
        _ => {}
    }
}

struct Stats {
    tool_calls: usize,
    errors: usize,
    tool_counts: std::collections::HashMap<String, usize>,
}

impl Stats {
    fn new() -> Self {
        Self {
            tool_calls: 0,
            errors: 0,
            tool_counts: std::collections::HashMap::new(),
        }
    }

    fn print_summary(&self) {
        println!();
        color_println(CYAN, "━━━ Session Summary ━━━");
        color_print(WHITE, &format!("  Tool calls: {}", self.tool_calls));
        if self.errors > 0 {
            color_print(RED, &format!("  Errors: {}", self.errors));
        }
        println!();

        let mut sorted: Vec<_> = self.tool_counts.iter().collect();
        sorted.sort_by(|a, b| b.1.cmp(a.1));
        for (name, count) in sorted.iter().take(8) {
            let color = tool_color(name);
            color_print(DIM, "  ");
            color_print(color, &format!("{name:<12}"));
            color_println(WHITE, &format!(" {count}"));
        }
    }
}

fn resolve_latest_session(dir: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(dir).ok()?;
    entries
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.path()
                .extension()
                .map(|ext| ext == "jsonl")
                .unwrap_or(false)
        })
        .max_by_key(|e| e.metadata().ok().and_then(|m| m.modified().ok()))
        .map(|e| e.path())
}

fn print_banner(path: &Path, follow: bool) {
    let (cols, _) = terminal::size().unwrap_or((80, 24));
    let line = "━".repeat(cols as usize);

    println!();
    color_println(CYAN, &line);
    color_println(
        CYAN,
        "  🔭 codeloop-watch — Claude Code Session Viewer",
    );
    color_print(DIM, "  File: ");
    color_println(WHITE, &path.to_string_lossy());
    if follow {
        color_print(DIM, "  Mode: ");
        color_println(GREEN, "LIVE (watching for changes)");
    } else {
        color_print(DIM, "  Mode: ");
        color_println(YELLOW, "REPLAY (reading existing log)");
    }
    color_println(CYAN, &line);
    println!();
}

fn main() {
    let args: Vec<String> = env::args().collect();

    let (path, follow, tail) = match args.len() {
        1 => {
            // No args: auto-detect latest session from current project
            let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            // Derive project dir name from cwd
            let cwd = env::current_dir().unwrap_or_default();
            let project_key = cwd
                .to_string_lossy()
                .replace('/', "-");
            let session_dir = format!("{home}/.claude/projects/{project_key}");
            let found = resolve_latest_session(&session_dir);
            match found {
                Some(p) => (p, true, true),
                None => {
                    eprintln!("Usage: codeloop-watch <session.jsonl> [--replay] [--all]");
                    eprintln!("       codeloop-watch  (auto-detects latest onefounder session)");
                    std::process::exit(1);
                }
            }
        }
        _ => {
            let path = PathBuf::from(&args[1]);
            let replay = args.iter().any(|a| a == "--replay");
            let all = args.iter().any(|a| a == "--all");
            (path, !replay, !all)
        }
    };

    if !path.exists() {
        eprintln!("File not found: {}", path.display());
        std::process::exit(1);
    }

    print_banner(&path, follow);

    let mut file = BufReader::new(File::open(&path).expect("Cannot open file"));
    let mut stats = Stats::new();

    if tail && follow {
        // Jump to last 200 lines for live mode
        let metadata = std::fs::metadata(&path).expect("Cannot read metadata");
        let size = metadata.len();
        let skip_to = if size > 100_000 { size - 100_000 } else { 0 };
        file.seek(SeekFrom::Start(skip_to)).ok();
        if skip_to > 0 {
            // Skip partial first line
            let mut discard = String::new();
            let _ = file.read_line(&mut discard);
            color_println(DIM, &format!("  (skipped to last ~100KB of {})", path.display()));
            println!();
        }
    }

    // Read existing content
    let mut line = String::new();
    loop {
        line.clear();
        match file.read_line(&mut line) {
            Ok(0) => break, // EOF
            Ok(_) => process_line(line.trim(), &mut stats),
            Err(_) => break,
        }
    }

    if !follow {
        stats.print_summary();
        return;
    }

    // Live tail mode
    color_println(GREEN, "  ▶ Watching for new activity...");
    println!();

    let mut last_size = std::fs::metadata(&path)
        .map(|m| m.len())
        .unwrap_or(0);

    loop {
        thread::sleep(Duration::from_millis(500));

        let current_size = match std::fs::metadata(&path) {
            Ok(m) => m.len(),
            Err(_) => continue,
        };

        if current_size > last_size {
            // Re-open to read new content (handles file rotation)
            if let Ok(f) = File::open(&path) {
                let mut reader = BufReader::new(f);
                reader.seek(SeekFrom::Start(last_size)).ok();

                let mut new_line = String::new();
                loop {
                    new_line.clear();
                    match reader.read_line(&mut new_line) {
                        Ok(0) => break,
                        Ok(_) => process_line(new_line.trim(), &mut stats),
                        Err(_) => break,
                    }
                }
            }
            last_size = current_size;
        }
    }
}
