import prismIncludeLanguagesOriginal from "@theme-original/prism-include-languages";

export default function prismIncludeLanguages(PrismObject) {
  // Load the default additionalLanguages from docusaurus.config.js
  prismIncludeLanguagesOriginal(PrismObject);

  // Register a custom "cosmos" language that highlights COSMOS configuration
  // keywords, ERB template tags, and embedded Ruby/Python snippets.
  // Keywords sourced from the OpenC3 VSCode extension:
  // https://github.com/JakeHillHub/openc3-vscode/tree/main/syntaxes
  PrismObject.languages["cosmos"] = {
    "erb-tag": {
      pattern: /<%=?[\s\S]*?%>/,
      greedy: true,
      inside: {
        delimiter: {
          pattern: /^<%=?|%>$/,
          alias: "punctuation",
        },
        string: {
          pattern: /"[^"]*"|'[^']*'/,
          greedy: true,
        },
        keyword: {
          pattern:
            /\b(?:require|include|render|each|do|end|if|else|elsif|unless|def|class|module)\b/,
        },
        variable: {
          pattern: /\b[a-z_]\w*\b/,
        },
        number: {
          pattern: /\b\d+(?:\.\d+)?\b/,
        },
        punctuation: {
          pattern: /[{}()[\];,.|]/,
        },
      },
    },
    comment: {
      pattern: /#.*/,
    },
    string: {
      pattern: /"[^"]*"|'[^']*'/,
      greedy: true,
    },
    // File paths (e.g. openc3/conversions/ip_write_conversion.py)
    "file-path": {
      pattern: /\b[\w/]+\.(?:py|rb|txt|json|csv|bin|gem)\b/,
      alias: "url",
    },
    // Top-level declarations (keyword.control in VSCode grammar)
    keyword: {
      pattern:
        /\b(?:COMMAND|TELEMETRY|SELECT_TELEMETRY|SELECT_COMMAND|LIMITS_GROUP|VARIABLE|NEEDS_DEPENDENCIES|INTERFACE|ROUTER|TARGET|MICROSERVICE|TOOL|WIDGET|SCRIPT_ENGINE|LANGUAGE|REQUIRE|IGNORE_PARAMETER|IGNORE_ITEM|COMMANDS|CMD_UNIQUE_ID_MODE|TLM_UNIQUE_ID_MODE|VALIDATOR)\b/,
    },
    // Parameters and items (entity.name.function in VSCode grammar)
    function: {
      pattern:
        /\b(?:(?:APPEND_)?(?:ID_)?(?:ARRAY_)?(?:PARAMETER|ITEM)|(?:SELECT|DELETE)_ITEM|GENERIC_READ_CONVERSION_START|GENERIC_READ_CONVERSION_END|GENERIC_WRITE_CONVERSION_START|GENERIC_WRITE_CONVERSION_END|MAP_TARGET|MAP_CMD_TARGET|MAP_TLM_TARGET|DONT_CONNECT|DONT_RECONNECT|RECONNECT_DELAY|DISABLE_DISCONNECT|LOG_RAW|LOG_STREAM|PROTOCOL|OPTION|SECRET|ENV|WORK_DIR|PORT|CMD|CONTAINER|ROUTE_PREFIX|CMD_BUFFER_DEPTH|CMD_LOG_CYCLE_TIME|CMD_LOG_CYCLE_SIZE|CMD_DECOM_LOG_CYCLE_TIME|CMD_DECOM_LOG_CYCLE_SIZE|CMD_DECOM_LOG_RETAIN_TIME|TLM_BUFFER_DEPTH|TLM_LOG_CYCLE_TIME|TLM_LOG_CYCLE_SIZE|TLM_LOG_RETAIN_TIME|TLM_DECOM_LOG_CYCLE_TIME|TLM_DECOM_LOG_CYCLE_SIZE|TLM_DECOM_LOG_RETAIN_TIME|REDUCED_MINUTE_LOG_RETAIN_TIME|REDUCED_HOUR_LOG_RETAIN_TIME|REDUCED_DAY_LOG_RETAIN_TIME|LOG_RETAIN_TIME|REDUCED_LOG_RETAIN_TIME|CLEANUP_POLL_TIME|REDUCER_DISABLE|REDUCER_MAX_CPU_UTILIZATION|TARGET_MICROSERVICE|PACKET|DISABLE_ERB|SHARD|TOPIC|TARGET_NAME|STOPPED|URL|INLINE_URL|WINDOW|ICON|CATEGORY|SHOWN|POSITION|IMPORT_MAP_ITEM|CONVERTED_DATA)\b/,
    },
    // Types and modifiers (entity.name.type in VSCode grammar)
    "class-name": {
      pattern:
        /\b(?:U?INT|FLOAT|BLOCK|STRING|DERIVED|STATE|LIMITS|LIMITS_GROUP_ITEM|FORMAT_STRING|UNITS|DESCRIPTION|META|OVERLAP|KEY|VARIABLE_BIT_SIZE|OBFUSCATE|REQUIRED|MINIMUM_VALUE|MAXIMUM_VALUE|DEFAULT_VALUE|OVERFLOW|DISABLE_MESSAGES|READ_CONVERSION|WRITE_CONVERSION|POLY_READ_CONVERSION|POLY_WRITE_CONVERSION|SEG_POLY_READ_CONVERSION|SEG_POLY_WRITE_CONVERSION|PROCESSOR|ALLOW_SHORT|HIDDEN|ACCESSOR|TEMPLATE|TEMPLATE_FILE|IGNORE|VIRTUAL|HAZARDOUS|DISABLED)\b/,
    },
    // Constants (constant.character in VSCode grammar)
    constant: {
      pattern:
        /\b(?:BIG_ENDIAN|LITTLE_ENDIAN|nil|(?:MAX|MIN)_(?:U?INT|FLOAT)(?:8|16|32|64|128))\b/,
    },
    boolean: {
      pattern: /\b(?:TRUE|FALSE|True|False|true|false)\b/,
    },
    number: {
      pattern: /\b(?:MIN|MAX|0x[\da-fA-F]+|\d+(?:\.\d+)?)\b/,
    },
    // Embedded Ruby/Python keywords for conversion blocks
    "ruby-keyword": {
      pattern:
        /\b(?:def|end|class|module|if|elsif|else|unless|while|until|for|do|begin|rescue|ensure|raise|return|yield|self|super|nil|require|include|extend|attr_accessor|attr_reader|attr_writer|puts|print|import|from|as|with|try|except|finally|lambda|pass|None|True|False|int|float|str|len|range|list|dict|set|tuple|isinstance|super)\b/,
      alias: "keyword",
    },
    // Common operators for embedded code
    operator: {
      pattern: /[=!<>]=?|[+\-*/%]|&&|\|\||\.\.\.?/,
    },
    punctuation: {
      pattern: /[{}()[\];,.:]/,
    },
  };
}
