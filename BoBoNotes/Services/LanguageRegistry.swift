import Foundation

/// Registry of all supported languages. Detects language from file extension.
final class LanguageRegistry {
    static let shared = LanguageRegistry()

    private(set) var languages: [LanguageDefinition] = []
    private var extensionMap: [String: String] = [:] // ext -> language id

    private init() {
        registerAll()
    }

    func language(forExtension ext: String) -> LanguageDefinition? {
        guard let id = extensionMap[ext.lowercased()] else { return nil }
        return languages.first { $0.id == id }
    }

    func language(forID id: String) -> LanguageDefinition? {
        languages.first { $0.id == id }
    }

    func detectLanguage(for url: URL?) -> LanguageDefinition? {
        guard let ext = url?.pathExtension.lowercased(), !ext.isEmpty else { return nil }
        return language(forExtension: ext)
    }

    // MARK: - Language Definitions
    // These computed properties are only called once during init() in registerAll().
    // After initialization, all access goes through the `languages` array.

    private func registerAll() {
        languages = [
            sql, plsql, bash, powershell, python, java, javascript, typescript,
            cLang, cpp, csharp, goLang, rust, php, ruby,
            html, css, xml, json, yaml, markdown,
            ini, toml, properties, log, swift, plainText
        ]

        for lang in languages {
            for ext in lang.extensions {
                extensionMap[ext.lowercased()] = lang.id
            }
        }
    }

    // ─── SQL ───
    var sql: LanguageDefinition {
        LanguageDefinition(
            id: "sql", displayName: "SQL",
            extensions: ["sql"],
            lineComment: "--", blockCommentStart: "/*", blockCommentEnd: "*/",
            keywords: ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
                       "TABLE", "INDEX", "VIEW", "TRIGGER", "PROCEDURE", "FUNCTION", "INTO", "VALUES",
                       "SET", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON", "AS", "AND", "OR",
                       "NOT", "NULL", "IS", "IN", "BETWEEN", "LIKE", "EXISTS", "HAVING", "GROUP", "BY",
                       "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "CASE",
                       "WHEN", "THEN", "ELSE", "END", "BEGIN", "COMMIT", "ROLLBACK", "GRANT", "REVOKE",
                       "WITH", "RECURSIVE", "REPLACE", "TRUNCATE", "MERGE", "USING", "MATCHED",
                       "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "UNIQUE", "CHECK", "DEFAULT",
                       "IF", "ELSE", "ELSIF", "LOOP", "WHILE", "FOR", "EXIT", "RETURN", "DECLARE",
                       "CURSOR", "FETCH", "OPEN", "CLOSE", "EXCEPTION", "RAISE", "PRAGMA",
                       "select", "from", "where", "insert", "update", "delete", "create", "alter", "drop",
                       "table", "index", "view", "join", "left", "right", "inner", "outer", "on", "as",
                       "and", "or", "not", "null", "is", "in", "between", "like", "exists", "having",
                       "group", "by", "order", "asc", "desc", "limit", "offset", "union", "all", "distinct",
                       "case", "when", "then", "else", "end", "begin", "commit", "rollback", "set", "into", "values"],
            types: ["INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC",
                    "VARCHAR", "VARCHAR2", "CHAR", "NVARCHAR", "NCHAR", "TEXT", "CLOB", "NCLOB", "BLOB",
                    "DATE", "DATETIME", "TIMESTAMP", "TIME", "INTERVAL", "BOOLEAN", "BOOL", "NUMBER",
                    "RAW", "LONG", "ROWID", "XMLTYPE", "JSON", "BINARY", "VARBINARY", "SERIAL", "UUID",
                    "int", "integer", "bigint", "varchar", "varchar2", "char", "text", "date", "number", "boolean"],
            builtinFunctions: ["COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NVL", "NVL2", "DECODE",
                               "TO_CHAR", "TO_DATE", "TO_NUMBER", "SYSDATE", "SYSTIMESTAMP", "CURRENT_DATE",
                               "SUBSTR", "INSTR", "LENGTH", "TRIM", "UPPER", "LOWER", "REPLACE", "CONCAT",
                               "ROUND", "TRUNC", "CEIL", "FLOOR", "MOD", "ABS", "POWER", "SQRT",
                               "RANK", "DENSE_RANK", "ROW_NUMBER", "LEAD", "LAG", "FIRST_VALUE", "LAST_VALUE",
                               "LISTAGG", "XMLAGG", "JSON_VALUE", "JSON_QUERY", "REGEXP_LIKE", "REGEXP_REPLACE",
                               "count", "sum", "avg", "min", "max", "coalesce", "nvl", "substr", "length", "trim",
                               "upper", "lower", "replace", "concat", "round", "trunc", "sysdate"],
            stringDelimiters: ["'"]
        )
    }

    // ─── PL/SQL ───
    var plsql: LanguageDefinition {
        LanguageDefinition(
            id: "plsql", displayName: "PL/SQL",
            extensions: ["pls", "plb", "pck", "pkb", "pks", "fnc", "prc", "trg", "typ"],
            lineComment: "--", blockCommentStart: "/*", blockCommentEnd: "*/",
            keywords: sql.keywords + ["PACKAGE", "BODY", "TYPE", "RECORD", "VARRAY", "NESTED", "BULK", "COLLECT",
                                       "FORALL", "SAVE", "EXCEPTIONS", "AUTONOMOUS_TRANSACTION", "PIPELINED",
                                       "PIPE", "ROW", "AUTHID", "CURRENT_USER", "DEFINER", "EXECUTE", "IMMEDIATE",
                                       "DBMS_OUTPUT", "PUT_LINE", "DBMS_SQL", "UTL_FILE"],
            types: sql.types + ["PLS_INTEGER", "BINARY_INTEGER", "SIMPLE_INTEGER", "SYS_REFCURSOR",
                                "DBMS_SQL.VARCHAR2_TABLE", "%TYPE", "%ROWTYPE"],
            builtinFunctions: sql.builtinFunctions,
            stringDelimiters: ["'"]
        )
    }

    // ─── Bash ───
    var bash: LanguageDefinition {
        LanguageDefinition(
            id: "bash", displayName: "Bash",
            extensions: ["sh", "bash", "zsh", "ksh"],
            lineComment: "#", blockCommentStart: nil, blockCommentEnd: nil,
            keywords: ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
                       "in", "function", "return", "local", "export", "source", "alias", "unalias",
                       "readonly", "declare", "typeset", "shift", "break", "continue", "eval", "exec",
                       "trap", "set", "unset", "exit", "test", "select", "until"],
            types: [],
            builtinFunctions: ["echo", "printf", "read", "cd", "pwd", "ls", "mkdir", "rm", "cp", "mv",
                               "cat", "grep", "sed", "awk", "find", "xargs", "sort", "uniq", "wc",
                               "head", "tail", "cut", "tr", "tee", "chmod", "chown", "curl", "wget"],
            stringDelimiters: ["\"", "'", "`"],
            preprocessorPrefix: "#!"
        )
    }

    // ─── PowerShell ───
    var powershell: LanguageDefinition {
        LanguageDefinition(
            id: "powershell", displayName: "PowerShell",
            extensions: ["ps1", "psm1", "psd1"],
            lineComment: "#", blockCommentStart: "<#", blockCommentEnd: "#>",
            keywords: ["if", "else", "elseif", "switch", "foreach", "for", "while", "do", "until",
                       "break", "continue", "return", "function", "param", "begin", "process", "end",
                       "try", "catch", "finally", "throw", "trap", "exit", "class", "enum", "using",
                       "filter", "workflow", "parallel", "sequence", "inlinescript"],
            types: ["string", "int", "bool", "array", "hashtable", "object", "void", "float", "double"],
            builtinFunctions: ["Get-Content", "Set-Content", "Write-Host", "Write-Output", "Read-Host",
                               "Get-Item", "Set-Item", "New-Item", "Remove-Item", "Copy-Item", "Move-Item",
                               "Get-Process", "Stop-Process", "Start-Process", "Get-Service", "Get-ChildItem",
                               "Select-Object", "Where-Object", "ForEach-Object", "Sort-Object", "Group-Object",
                               "Invoke-Command", "Invoke-Expression", "Import-Module", "Export-ModuleMember"],
            stringDelimiters: ["\"", "'"]
        )
    }

    // ─── Python ───
    var python: LanguageDefinition {
        LanguageDefinition(
            id: "python", displayName: "Python",
            extensions: ["py", "pyw", "pyi"],
            lineComment: "#", blockCommentStart: nil, blockCommentEnd: nil,
            keywords: ["False", "None", "True", "and", "as", "assert", "async", "await", "break",
                       "class", "continue", "def", "del", "elif", "else", "except", "finally",
                       "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal",
                       "not", "or", "pass", "raise", "return", "try", "while", "with", "yield",
                       "match", "case", "type"],
            types: ["int", "float", "str", "bool", "list", "dict", "tuple", "set", "bytes",
                    "bytearray", "complex", "frozenset", "range", "memoryview", "object", "type"],
            builtinFunctions: ["print", "len", "range", "type", "isinstance", "issubclass", "hasattr",
                               "getattr", "setattr", "delattr", "open", "input", "map", "filter",
                               "zip", "enumerate", "sorted", "reversed", "min", "max", "sum", "abs",
                               "round", "pow", "divmod", "hex", "oct", "bin", "chr", "ord", "repr", "str",
                               "int", "float", "bool", "list", "dict", "tuple", "set", "super", "next",
                               "iter", "all", "any", "dir", "vars", "globals", "locals", "id", "hash"],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: "\"\"\"[\\s\\S]*?\"\"\"", tokenType: .string),
                .init(pattern: "'''[\\s\\S]*?'''", tokenType: .string),
                .init(pattern: "@\\w+", tokenType: .attribute),
                .init(pattern: "\\bself\\b", tokenType: .variable),
            ]
        )
    }

    // ─── Java ───
    var java: LanguageDefinition {
        LanguageDefinition(
            id: "java", displayName: "Java",
            extensions: ["java"],
            keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
                       "class", "const", "continue", "default", "do", "double", "else", "enum",
                       "extends", "final", "finally", "float", "for", "goto", "if", "implements",
                       "import", "instanceof", "int", "interface", "long", "native", "new", "package",
                       "private", "protected", "public", "return", "short", "static", "strictfp",
                       "super", "switch", "synchronized", "this", "throw", "throws", "transient",
                       "try", "void", "volatile", "while", "var", "yield", "record", "sealed",
                       "permits", "non-sealed"],
            types: ["String", "Integer", "Long", "Double", "Float", "Boolean", "Character", "Byte",
                    "Short", "Object", "Class", "List", "Map", "Set", "ArrayList", "HashMap",
                    "HashSet", "Optional", "Stream", "Collection", "Iterable", "Iterator"],
            builtinFunctions: ["System.out.println", "System.out.print", "System.err.println",
                               "Math.abs", "Math.max", "Math.min", "Arrays.sort", "Collections.sort"],
            preprocessorPrefix: "@",
            extraRules: [
                .init(pattern: "@\\w+", tokenType: .attribute),
            ]
        )
    }

    // ─── JavaScript ───
    var javascript: LanguageDefinition {
        LanguageDefinition(
            id: "javascript", displayName: "JavaScript",
            extensions: ["js", "mjs", "cjs", "jsx"],
            keywords: ["break", "case", "catch", "class", "const", "continue", "debugger", "default",
                       "delete", "do", "else", "export", "extends", "false", "finally", "for",
                       "function", "if", "import", "in", "instanceof", "let", "new", "null", "of",
                       "return", "static", "super", "switch", "this", "throw", "true", "try",
                       "typeof", "undefined", "var", "void", "while", "with", "yield", "async", "await",
                       "from", "as", "get", "set"],
            types: ["Array", "Boolean", "Date", "Error", "Function", "JSON", "Map", "Math", "Number",
                    "Object", "Promise", "Proxy", "RegExp", "Set", "String", "Symbol", "WeakMap", "WeakSet"],
            builtinFunctions: ["console.log", "console.error", "console.warn", "parseInt", "parseFloat",
                               "isNaN", "isFinite", "setTimeout", "setInterval", "clearTimeout", "clearInterval",
                               "fetch", "require", "alert", "confirm", "prompt"],
            stringDelimiters: ["\"", "'", "`"],
            extraRules: [
                .init(pattern: "=>[\\s]", tokenType: .operator),
                .init(pattern: "`[^`]*`", tokenType: .string),
            ]
        )
    }

    // ─── TypeScript ───
    var typescript: LanguageDefinition {
        LanguageDefinition(
            id: "typescript", displayName: "TypeScript",
            extensions: ["ts", "tsx"],
            keywords: javascript.keywords + ["type", "interface", "enum", "namespace", "module",
                                              "declare", "abstract", "implements", "readonly", "keyof",
                                              "infer", "is", "asserts", "override", "satisfies"],
            types: javascript.types + ["any", "unknown", "never", "void", "bigint", "symbol",
                                        "Partial", "Required", "Readonly", "Record", "Pick", "Omit",
                                        "Exclude", "Extract", "NonNullable", "ReturnType", "InstanceType"],
            builtinFunctions: javascript.builtinFunctions,
            stringDelimiters: ["\"", "'", "`"]
        )
    }

    // ─── C ───
    var cLang: LanguageDefinition {
        LanguageDefinition(
            id: "c", displayName: "C",
            extensions: ["c", "h"],
            keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do",
                       "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
                       "int", "long", "register", "restrict", "return", "short", "signed", "sizeof",
                       "static", "struct", "switch", "typedef", "union", "unsigned", "void",
                       "volatile", "while", "_Bool", "_Complex", "_Imaginary", "_Alignas",
                       "_Alignof", "_Atomic", "_Generic", "_Noreturn", "_Static_assert", "_Thread_local"],
            types: ["size_t", "ptrdiff_t", "int8_t", "int16_t", "int32_t", "int64_t",
                    "uint8_t", "uint16_t", "uint32_t", "uint64_t", "FILE", "NULL",
                    "bool", "true", "false"],
            builtinFunctions: ["printf", "scanf", "malloc", "calloc", "realloc", "free",
                               "memcpy", "memmove", "memset", "strlen", "strcpy", "strcat",
                               "strcmp", "fopen", "fclose", "fread", "fwrite", "fprintf", "fscanf"],
            preprocessorPrefix: "#",
            extraRules: [
                .init(pattern: "#\\s*(include|define|undef|ifdef|ifndef|if|elif|else|endif|pragma|error|warning)\\b", tokenType: .preprocessor),
            ]
        )
    }

    // ─── C++ ───
    var cpp: LanguageDefinition {
        LanguageDefinition(
            id: "cpp", displayName: "C++",
            extensions: ["cpp", "cxx", "cc", "hpp", "hxx", "hh"],
            keywords: cLang.keywords + ["alignas", "alignof", "and", "and_eq", "asm", "bitand",
                                         "bitor", "bool", "catch", "class", "compl", "concept",
                                         "consteval", "constexpr", "constinit", "co_await", "co_return",
                                         "co_yield", "decltype", "delete", "dynamic_cast", "explicit",
                                         "export", "false", "friend", "mutable", "namespace", "new",
                                         "noexcept", "not", "not_eq", "nullptr", "operator", "or",
                                         "or_eq", "private", "protected", "public", "reinterpret_cast",
                                         "requires", "static_assert", "static_cast", "template",
                                         "this", "throw", "true", "try", "typeid", "typename",
                                         "using", "virtual", "xor", "xor_eq", "override", "final"],
            types: cLang.types + ["string", "vector", "map", "unordered_map", "set", "unordered_set",
                                   "list", "deque", "queue", "stack", "pair", "tuple", "array",
                                   "shared_ptr", "unique_ptr", "weak_ptr", "optional", "variant",
                                   "any", "span", "string_view", "iostream", "ostream", "istream"],
            builtinFunctions: cLang.builtinFunctions + ["cout", "cin", "endl", "cerr", "clog",
                                                         "make_shared", "make_unique", "move", "forward",
                                                         "static_cast", "dynamic_cast", "const_cast"],
            preprocessorPrefix: "#",
            extraRules: cLang.extraRules
        )
    }

    // ─── C# ───
    var csharp: LanguageDefinition {
        LanguageDefinition(
            id: "csharp", displayName: "C#",
            extensions: ["cs"],
            keywords: ["abstract", "as", "base", "bool", "break", "byte", "case", "catch",
                       "char", "checked", "class", "const", "continue", "decimal", "default",
                       "delegate", "do", "double", "else", "enum", "event", "explicit", "extern",
                       "false", "finally", "fixed", "float", "for", "foreach", "goto", "if",
                       "implicit", "in", "int", "interface", "internal", "is", "lock", "long",
                       "namespace", "new", "null", "object", "operator", "out", "override",
                       "params", "private", "protected", "public", "readonly", "ref", "return",
                       "sbyte", "sealed", "short", "sizeof", "stackalloc", "static", "string",
                       "struct", "switch", "this", "throw", "true", "try", "typeof", "uint",
                       "ulong", "unchecked", "unsafe", "ushort", "using", "var", "virtual",
                       "void", "volatile", "while", "async", "await", "record", "init", "required",
                       "with", "yield", "when", "where", "from", "select", "let", "join", "into",
                       "orderby", "ascending", "descending", "group", "by"],
            types: ["String", "Int32", "Int64", "Double", "Float", "Boolean", "Char", "Byte",
                    "Object", "List", "Dictionary", "HashSet", "Queue", "Stack", "Array",
                    "Task", "ValueTask", "IEnumerable", "IList", "IDictionary", "Func", "Action",
                    "Nullable", "Span", "Memory", "ReadOnlySpan"],
            builtinFunctions: ["Console.WriteLine", "Console.Write", "Console.ReadLine",
                               "Math.Abs", "Math.Max", "Math.Min", "Convert.ToInt32"],
            extraRules: [
                .init(pattern: "@\"[^\"]*\"", tokenType: .string),
                .init(pattern: "\\[\\w+\\]", tokenType: .attribute),
            ]
        )
    }

    // ─── Go ───
    var goLang: LanguageDefinition {
        LanguageDefinition(
            id: "go", displayName: "Go",
            extensions: ["go"],
            keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else",
                       "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
                       "map", "package", "range", "return", "select", "struct", "switch", "type",
                       "var"],
            types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64",
                    "int", "int8", "int16", "int32", "int64", "rune", "string",
                    "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any", "comparable"],
            builtinFunctions: ["append", "cap", "close", "complex", "copy", "delete", "imag",
                               "len", "make", "new", "panic", "print", "println", "real", "recover"],
            stringDelimiters: ["\"", "'", "`"]
        )
    }

    // ─── Rust ───
    var rust: LanguageDefinition {
        LanguageDefinition(
            id: "rust", displayName: "Rust",
            extensions: ["rs"],
            keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn",
                       "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in",
                       "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
                       "self", "Self", "static", "struct", "super", "trait", "true", "type",
                       "unsafe", "use", "where", "while", "yield", "macro_rules"],
            types: ["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize",
                    "str", "u8", "u16", "u32", "u64", "u128", "usize", "String", "Vec", "Box",
                    "Option", "Result", "HashMap", "HashSet", "Rc", "Arc", "Mutex", "Cell",
                    "RefCell", "Pin", "Future", "Iterator"],
            builtinFunctions: ["println", "eprintln", "format", "panic", "assert", "assert_eq",
                               "assert_ne", "todo", "unimplemented", "unreachable", "dbg", "vec",
                               "include_str", "include_bytes", "env", "cfg", "compile_error"],
            extraRules: [
                .init(pattern: "#\\[\\w+[^\\]]*\\]", tokenType: .attribute),
                .init(pattern: "\\b(Some|None|Ok|Err)\\b", tokenType: .type),
            ]
        )
    }

    // ─── PHP ───
    var php: LanguageDefinition {
        LanguageDefinition(
            id: "php", displayName: "PHP",
            extensions: ["php", "phtml"],
            lineComment: "//", blockCommentStart: "/*", blockCommentEnd: "*/",
            keywords: ["abstract", "and", "array", "as", "break", "callable", "case", "catch",
                       "class", "clone", "const", "continue", "declare", "default", "die", "do",
                       "echo", "else", "elseif", "empty", "enddeclare", "endfor", "endforeach",
                       "endif", "endswitch", "endwhile", "eval", "exit", "extends", "final",
                       "finally", "fn", "for", "foreach", "function", "global", "goto", "if",
                       "implements", "include", "include_once", "instanceof", "insteadof",
                       "interface", "isset", "list", "match", "namespace", "new", "null", "or",
                       "print", "private", "protected", "public", "readonly", "require",
                       "require_once", "return", "static", "switch", "throw", "trait", "try",
                       "unset", "use", "var", "while", "xor", "yield", "yield from",
                       "true", "false", "null", "self", "parent"],
            types: ["int", "float", "string", "bool", "array", "object", "void", "never",
                    "mixed", "null", "iterable", "callable"],
            builtinFunctions: ["echo", "print", "var_dump", "print_r", "isset", "empty", "unset",
                               "strlen", "strpos", "substr", "str_replace", "array_push", "array_pop",
                               "array_merge", "array_map", "array_filter", "count", "sort", "rsort",
                               "implode", "explode", "json_encode", "json_decode"],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: "\\$\\w+", tokenType: .variable),
            ]
        )
    }

    // ─── Ruby ───
    var ruby: LanguageDefinition {
        LanguageDefinition(
            id: "ruby", displayName: "Ruby",
            extensions: ["rb", "rake", "gemspec"],
            lineComment: "#", blockCommentStart: "=begin", blockCommentEnd: "=end",
            keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?",
                       "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in",
                       "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return",
                       "self", "super", "then", "true", "undef", "unless", "until", "when",
                       "while", "yield", "raise", "require", "require_relative", "include",
                       "extend", "prepend", "attr_accessor", "attr_reader", "attr_writer",
                       "private", "protected", "public"],
            types: ["String", "Integer", "Float", "Array", "Hash", "Symbol", "Regexp",
                    "TrueClass", "FalseClass", "NilClass", "Proc", "Lambda", "IO", "File"],
            builtinFunctions: ["puts", "print", "p", "pp", "gets", "chomp", "each", "map", "select",
                               "reject", "reduce", "inject", "collect", "detect", "find", "sort",
                               "sort_by", "flat_map", "compact", "uniq", "reverse", "join", "split"],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: ":\\w+", tokenType: .string),  // Symbols
                .init(pattern: "@{1,2}\\w+", tokenType: .variable),
            ]
        )
    }

    // ─── HTML ───
    var html: LanguageDefinition {
        LanguageDefinition(
            id: "html", displayName: "HTML",
            extensions: ["html", "htm", "xhtml"],
            lineComment: nil, blockCommentStart: "<!--", blockCommentEnd: "-->",
            keywords: ["doctype", "html", "head", "body", "div", "span", "p", "a", "img",
                       "ul", "ol", "li", "table", "tr", "td", "th", "form", "input", "button",
                       "select", "option", "textarea", "label", "script", "style", "link",
                       "meta", "title", "header", "footer", "nav", "main", "section", "article",
                       "aside", "h1", "h2", "h3", "h4", "h5", "h6", "br", "hr", "pre", "code",
                       "strong", "em", "b", "i", "u", "small", "sub", "sup", "iframe", "video", "audio"],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: "</?\\w+", tokenType: .keyword),
                .init(pattern: "\\w+\\s*=", tokenType: .attribute),
            ]
        )
    }

    // ─── CSS ───
    var css: LanguageDefinition {
        LanguageDefinition(
            id: "css", displayName: "CSS",
            extensions: ["css", "scss", "sass", "less"],
            lineComment: nil, blockCommentStart: "/*", blockCommentEnd: "*/",
            keywords: ["@import", "@media", "@keyframes", "@font-face", "@charset", "@supports",
                       "@page", "@namespace", "@layer", "@container", "@property",
                       "!important", "inherit", "initial", "unset", "revert"],
            types: [],
            builtinFunctions: ["rgb", "rgba", "hsl", "hsla", "calc", "var", "min", "max", "clamp",
                               "url", "linear-gradient", "radial-gradient", "conic-gradient",
                               "attr", "counter", "env", "minmax", "repeat", "fit-content"],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: "#[0-9a-fA-F]{3,8}\\b", tokenType: .number),
                .init(pattern: "\\.[a-zA-Z_][\\w-]*", tokenType: .type),
                .init(pattern: "#[a-zA-Z_][\\w-]*", tokenType: .attribute),
            ]
        )
    }

    // ─── XML ───
    var xml: LanguageDefinition {
        LanguageDefinition(
            id: "xml", displayName: "XML",
            extensions: ["xml", "xsl", "xslt", "xsd", "wsdl", "svg", "plist"],
            lineComment: nil, blockCommentStart: "<!--", blockCommentEnd: "-->",
            keywords: [],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: "</?[\\w:-]+", tokenType: .keyword),
                .init(pattern: "[\\w:-]+\\s*=", tokenType: .attribute),
                .init(pattern: "<\\?[\\w]+", tokenType: .preprocessor),
                .init(pattern: "\\?>", tokenType: .preprocessor),
            ]
        )
    }

    // ─── JSON ───
    var json: LanguageDefinition {
        LanguageDefinition(
            id: "json", displayName: "JSON",
            extensions: ["json", "jsonc", "json5"],
            lineComment: nil, blockCommentStart: nil, blockCommentEnd: nil,
            keywords: ["true", "false", "null"],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\""],
            extraRules: [
                .init(pattern: "\"[^\"]*\"\\s*:", tokenType: .attribute),
            ]
        )
    }

    // ─── YAML ───
    var yaml: LanguageDefinition {
        LanguageDefinition(
            id: "yaml", displayName: "YAML",
            extensions: ["yaml", "yml"],
            lineComment: "#", blockCommentStart: nil, blockCommentEnd: nil,
            keywords: ["true", "false", "null", "yes", "no", "on", "off"],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: "^\\s*[\\w.-]+\\s*:", tokenType: .attribute),
                .init(pattern: "&\\w+", tokenType: .variable),
                .init(pattern: "\\*\\w+", tokenType: .variable),
            ]
        )
    }

    // ─── Markdown ───
    var markdown: LanguageDefinition {
        LanguageDefinition(
            id: "markdown", displayName: "Markdown",
            extensions: ["md", "markdown", "mdown", "mkd"],
            lineComment: nil, blockCommentStart: nil, blockCommentEnd: nil,
            keywords: [],
            types: [],
            builtinFunctions: [],
            stringDelimiters: [],
            extraRules: [
                .init(pattern: "^#{1,6}\\s+.*$", tokenType: .keyword),
                .init(pattern: "\\*\\*[^*]+\\*\\*", tokenType: .keyword),
                .init(pattern: "\\*[^*]+\\*", tokenType: .string),
                .init(pattern: "`[^`]+`", tokenType: .function),
                .init(pattern: "```[\\s\\S]*?```", tokenType: .function),
                .init(pattern: "\\[([^\\]]+)\\]\\([^)]+\\)", tokenType: .attribute),
            ]
        )
    }

    // ─── INI ───
    var ini: LanguageDefinition {
        LanguageDefinition(
            id: "ini", displayName: "INI",
            extensions: ["ini", "cfg", "conf"],
            lineComment: ";", blockCommentStart: nil, blockCommentEnd: nil,
            keywords: ["true", "false", "yes", "no", "on", "off"],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\""],
            extraRules: [
                .init(pattern: "^\\s*\\[[^\\]]+\\]", tokenType: .keyword),
                .init(pattern: "^\\s*[\\w.-]+\\s*=", tokenType: .attribute),
            ]
        )
    }

    // ─── TOML ───
    var toml: LanguageDefinition {
        LanguageDefinition(
            id: "toml", displayName: "TOML",
            extensions: ["toml"],
            lineComment: "#", blockCommentStart: nil, blockCommentEnd: nil,
            keywords: ["true", "false"],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\"", "'"],
            extraRules: [
                .init(pattern: "^\\s*\\[\\[?[^\\]]+\\]\\]?", tokenType: .keyword),
                .init(pattern: "^\\s*[\\w.-]+\\s*=", tokenType: .attribute),
            ]
        )
    }

    // ─── Properties ───
    var properties: LanguageDefinition {
        LanguageDefinition(
            id: "properties", displayName: "Properties",
            extensions: ["properties", "env"],
            lineComment: "#", blockCommentStart: nil, blockCommentEnd: nil,
            keywords: [],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\""],
            extraRules: [
                .init(pattern: "^[\\w.-]+\\s*[=:]", tokenType: .attribute),
            ]
        )
    }

    // ─── Log ───
    var log: LanguageDefinition {
        LanguageDefinition(
            id: "log", displayName: "Log",
            extensions: ["log"],
            lineComment: nil, blockCommentStart: nil, blockCommentEnd: nil,
            keywords: ["ERROR", "WARN", "WARNING", "INFO", "DEBUG", "TRACE", "FATAL", "CRITICAL",
                       "SEVERE", "FINE", "FINER", "FINEST", "NOTICE", "ALERT", "EMERGENCY",
                       "error", "warn", "warning", "info", "debug", "trace", "fatal"],
            types: [],
            builtinFunctions: [],
            stringDelimiters: ["\""],
            extraRules: [
                .init(pattern: "\\d{4}[-/]\\d{2}[-/]\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}", tokenType: .number),
                .init(pattern: "\\b(?:ERROR|FATAL|CRITICAL|SEVERE)\\b", tokenType: .keyword),
                .init(pattern: "\\b(?:WARN|WARNING)\\b", tokenType: .type),
                .init(pattern: "\\b(?:INFO|NOTICE)\\b", tokenType: .function),
                .init(pattern: "\\b(?:DEBUG|TRACE|FINE|FINER|FINEST)\\b", tokenType: .comment),
            ]
        )
    }

    // ─── Swift ───
    var swift: LanguageDefinition {
        LanguageDefinition(
            id: "swift", displayName: "Swift",
            extensions: ["swift"],
            keywords: ["actor", "any", "as", "associatedtype", "async", "await", "break", "case",
                       "catch", "class", "consume", "consuming", "continue", "convenience",
                       "default", "defer", "deinit", "do", "dynamic", "else", "enum", "extension",
                       "fallthrough", "false", "fileprivate", "final", "for", "func", "guard",
                       "if", "import", "in", "indirect", "infix", "init", "inout", "internal",
                       "is", "isolated", "lazy", "let", "macro", "mutating", "nil", "nonisolated",
                       "nonmutating", "open", "operator", "optional", "override", "postfix",
                       "precedencegroup", "prefix", "private", "protocol", "public", "repeat",
                       "required", "rethrows", "return", "self", "Self", "some", "static",
                       "struct", "subscript", "super", "switch", "throw", "throws", "true",
                       "try", "typealias", "unowned", "var", "weak", "where", "while"],
            types: ["String", "Int", "Double", "Float", "Bool", "Character", "Array", "Dictionary",
                    "Set", "Optional", "Result", "Error", "Codable", "Encodable", "Decodable",
                    "Identifiable", "Hashable", "Equatable", "Comparable", "Sequence", "Collection",
                    "AsyncSequence", "Task", "MainActor", "Sendable", "ObservableObject",
                    "Published", "State", "Binding", "Environment", "EnvironmentObject",
                    "View", "some View", "Never", "Void", "Any", "AnyObject"],
            builtinFunctions: ["print", "debugPrint", "dump", "fatalError", "precondition",
                               "preconditionFailure", "assert", "assertionFailure", "min", "max",
                               "abs", "stride", "zip", "type", "unsafeBitCast", "withUnsafePointer"],
            extraRules: [
                .init(pattern: "@\\w+", tokenType: .attribute),
                .init(pattern: "#\\w+", tokenType: .preprocessor),
            ]
        )
    }

    // ─── Plain Text ───
    var plainText: LanguageDefinition {
        LanguageDefinition(
            id: "plain", displayName: "Plain Text",
            extensions: ["txt", "text"],
            lineComment: nil, blockCommentStart: nil, blockCommentEnd: nil,
            keywords: [], types: [], builtinFunctions: [],
            operators: [], stringDelimiters: []
        )
    }
}
