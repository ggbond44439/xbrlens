///|
pub(all) enum CliCommand {
  Help
  Version
  Inspect
  Facts
  Validate
  Calc
  Diff
} derive(Eq, @debug.Debug)

///|
pub(all) struct CliInvocation {
  command : CliCommand
  args : Array[String]
  json : Bool
  csv : Bool
  help : Bool
} derive(Eq, @debug.Debug)

///|
pub(all) enum CliError {
  UnknownCommand(String)
  UnknownOption(String)
  MissingArgument(String)
} derive(Eq, @debug.Debug)

///|
pub impl Show for CliError with fn output(self, logger) {
  match self {
    UnknownCommand(name) =>
      logger.write_string("unknown command '" + name + "'")
    UnknownOption(name) => logger.write_string("unknown option '" + name + "'")
    MissingArgument(name) =>
      logger.write_string("missing argument for '" + name + "'")
  }
}

///|
pub(all) struct CliResult {
  exit_code : Int32
  stdout : String
  stderr : String
} derive(Eq, @debug.Debug)

///|
pub fn CliResult::success(stdout : String) -> CliResult {
  { exit_code: 0, stdout, stderr: "", }
}

///|
pub fn CliResult::failure(code : Int32, stderr : String) -> CliResult {
  { exit_code: code, stdout: "", stderr, }
}

///|
pub fn cli_help_text() -> String {
  (
    $|XBRLens - auditable XBRL parsing and validation
    $|
    $|Usage:
    $|  xbrlens inspect <instance-xml>
    $|  xbrlens facts [--csv] <instance-xml>
    $|  xbrlens validate <instance-xml>
    $|  xbrlens calc <instance-xml> <taxonomy-xml> <linkbase-xml>
    $|  xbrlens diff <left-instance-xml> <right-instance-xml>
    $|  xbrlens version
    $|
    $|Global options:
    $|  --json      Emit machine-readable output where supported
    $|  --csv       Emit CSV for the facts command
    $|  --help, -h  Show help
  )
}

///|
pub fn parse_invocation(
  args : ArrayView[String],
) -> Result[CliInvocation, CliError] {
  let positional : Array[String] = []
  let mut json = false
  let mut csv = false
  let mut help = false
  for arg in args {
    match arg {
      "--json" => json = true
      "--csv" => csv = true
      "--help" | "-h" => help = true
      _ =>
        if arg.has_prefix("-") {
          return Err(UnknownOption(arg))
        } else {
          positional.push(arg)
        }
    }
  }
  if positional.is_empty() {
    return Ok({ command: Help, args: [], json, csv, help, })
  }
  let command_name = positional[0]
  let command = match command_name {
    "help" => Help
    "version" => Version
    "inspect" => Inspect
    "facts" => Facts
    "validate" => Validate
    "calc" => Calc
    "diff" => Diff
    _ => return Err(UnknownCommand(command_name))
  }
  let rest : Array[String] = []
  for index in 1..<positional.length() {
    rest.push(positional[index])
  }
  Ok({ command, args: rest, json, csv, help, })
}

///|
fn require_cli_args(
  invocation : CliInvocation,
  count : Int32,
  description : String,
) -> Result[Unit, CliError] {
  if invocation.args.length() < count {
    Err(MissingArgument(description))
  } else {
    Ok(())
  }
}

///|
fn strict_instance(source : String) -> Result[XbrlInstance, XbrlError] {
  parse_instance_xml(source, XbrlLimits::strict())
}

///|
fn run_inspect(invocation : CliInvocation) -> CliResult {
  match require_cli_args(invocation, 1, "instance XML") {
    Ok(_) => ()
    Err(err) => return CliResult::failure(2, "xbrlens: " + err.to_string())
  }
  let instance = match strict_instance(invocation.args[0]) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  if invocation.json {
    CliResult::success(
      "{\"contexts\":" +
      instance.contexts.length().to_string() +
      ",\"units\":" +
      instance.units.length().to_string() +
      ",\"facts\":" +
      instance.facts.length().to_string() +
      ",\"schemaRefs\":" +
      instance.schema_refs.length().to_string() +
      "}",
    )
  } else {
    CliResult::success(
      (
        $|contexts: \{instance.contexts.length()}
        $|units: \{instance.units.length()}
        $|facts: \{instance.facts.length()}
        $|schema_refs: \{instance.schema_refs.length()}
      ),
    )
  }
}

///|
fn run_facts(invocation : CliInvocation) -> CliResult {
  match require_cli_args(invocation, 1, "instance XML") {
    Ok(_) => ()
    Err(err) => return CliResult::failure(2, "xbrlens: " + err.to_string())
  }
  let instance = match strict_instance(invocation.args[0]) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let output = if invocation.csv {
    export_csv(instance)
  } else {
    export_json(instance)
  }
  match output {
    Ok(value) => CliResult::success(value)
    Err(err) => CliResult::failure(1, err.to_string())
  }
}

///|
fn diagnostic_kind_name(kind : FactDiagnosticKind) -> String {
  match kind {
    ExactDuplicate => "exact-duplicate"
    ConflictingDuplicate => "conflicting-duplicate"
    NilConflict => "nil-conflict"
    MultipleUnits => "multiple-units"
    DecimalsPrecisionConflict => "decimals-precision-conflict"
    InvalidDecimals => "invalid-decimals"
    InvalidPrecision => "invalid-precision"
  }
}

///|
fn run_validate(invocation : CliInvocation) -> CliResult {
  match require_cli_args(invocation, 1, "instance XML") {
    Ok(_) => ()
    Err(err) => return CliResult::failure(2, "xbrlens: " + err.to_string())
  }
  let instance = match strict_instance(invocation.args[0]) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let report = instance.fact_integrity()
  if invocation.json {
    let builder = StringBuilder()
    builder.write_string("{\"valid\":")
    builder.write_string(if report.has_errors() { "false" } else { "true" })
    builder.write_string(",\"errors\":")
    builder.write_string(report.error_count().to_string())
    builder.write_string(",\"warnings\":")
    builder.write_string(report.warning_count().to_string())
    builder.write_string(",\"diagnostics\":[")
    let mut index = 0
    while index < report.diagnostics.length() {
      if index > 0 {
        builder.write_char(',')
      }
      let diagnostic = report.diagnostics[index]
      builder.write_string("{\"kind\":")
      builder.write_string(json_quote(diagnostic_kind_name(diagnostic.kind)))
      builder.write_string(",\"severity\":")
      builder.write_string(
        json_quote(
          if diagnostic.severity == Error {
            "error"
          } else {
            "warning"
          },
        ),
      )
      builder.write_string(",\"message\":")
      builder.write_string(json_quote(diagnostic.message))
      builder.write_char('}')
      index += 1
    }
    builder.write_string("]}")
    CliResult::success(builder.to_string())
  } else {
    let builder = StringBuilder()
    builder.write_string("errors: " + report.error_count().to_string() + "\n")
    builder.write_string("warnings: " + report.warning_count().to_string())
    for diagnostic in report.diagnostics {
      builder.write_string("\n")
      builder.write_string(
        if diagnostic.severity == Error {
          "error: "
        } else {
          "warning: "
        },
      )
      builder.write_string(diagnostic_kind_name(diagnostic.kind))
      builder.write_string(": ")
      builder.write_string(diagnostic.message)
    }
    if report.has_errors() {
      CliResult::failure(1, builder.to_string())
    } else {
      CliResult::success(builder.to_string())
    }
  }
} ///|

///|
fn run_calc(invocation : CliInvocation) -> CliResult {
  match
    require_cli_args(
      invocation, 3, "instance XML, taxonomy XML, and linkbase XML",
    ) {
    Ok(_) => ()
    Err(err) => return CliResult::failure(2, "xbrlens: " + err.to_string())
  }
  let instance = match strict_instance(invocation.args[0]) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let schema = match
    parse_taxonomy_xml(invocation.args[1], XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let taxonomy : ResolvedTaxonomy = {
    root_location: "inline-taxonomy.xsd",
    schemas: [
      { location: "inline-taxonomy.xsd", schema, source: invocation.args[1], },
    ],
  }
  let linkbase = match
    parse_linkbase_xml(invocation.args[2], XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let report = match check_calculations(linkbase, taxonomy, instance) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  if invocation.json {
    CliResult::success(
      "{\"valid\":" +
      (if report.is_valid() { "true" } else { "false" }) +
      ",\"checks\":" +
      report.checks.length().to_string() +
      ",\"mismatches\":" +
      report.mismatches().length().to_string() +
      "}",
    )
  } else {
    let builder = StringBuilder()
    builder.write_string("checks: " + report.checks.length().to_string())
    for check in report.checks {
      builder.write_string("\n")
      builder.write_string(if check.matched { "ok: " } else { "mismatch: " })
      builder.write_string(check.parent.expanded())
      builder.write_string(" context=")
      builder.write_string(check.context_ref)
      builder.write_string(" expected=")
      builder.write_string(check.expected.to_canonical_string())
      builder.write_string(" expected_range=[")
      builder.write_string(check.expected_low.to_canonical_string())
      builder.write_string(",")
      builder.write_string(check.expected_high.to_canonical_string())
      builder.write_string("] actual=")
      builder.write_string(check.actual.to_canonical_string())
      builder.write_string(" actual_range=[")
      builder.write_string(check.actual_low.to_canonical_string())
      builder.write_string(",")
      builder.write_string(check.actual_high.to_canonical_string())
      builder.write_string("]")
    }
    if report.is_valid() {
      CliResult::success(builder.to_string())
    } else {
      CliResult::failure(1, builder.to_string())
    }
  }
}

///|
fn fact_diff_key(row : FactExportRow) -> String {
  let value = match row.canonical_value {
    Some(value) => value
    None => row.value
  }
  let unit = match row.unit_ref {
    Some(value) => value
    None => ""
  }
  row.concept + "|" + row.context_ref + "|" + unit + "|" + value
}

///|
fn count_fact_key(rows : Array[FactExportRow], key : String) -> Int32 {
  let mut count = 0
  for row in rows {
    if fact_diff_key(row) == key {
      count += 1
    }
  }
  count
}

///|
fn difference_count(
  left : Array[FactExportRow],
  right : Array[FactExportRow],
) -> Int32 {
  let seen : Array[String] = []
  let mut count = 0
  for row in left {
    let key = fact_diff_key(row)
    let mut already_seen = false
    for existing in seen {
      if existing == key {
        already_seen = true
      }
    }
    if !already_seen {
      seen.push(key)
      let left_count = count_fact_key(left, key)
      let right_count = count_fact_key(right, key)
      if left_count > right_count {
        count += left_count - right_count
      }
    }
  }
  count
}

///|
fn run_diff(invocation : CliInvocation) -> CliResult {
  match require_cli_args(invocation, 2, "left and right instance XML") {
    Ok(_) => ()
    Err(err) => return CliResult::failure(2, "xbrlens: " + err.to_string())
  }
  let left_instance = match strict_instance(invocation.args[0]) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let right_instance = match strict_instance(invocation.args[1]) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let left = match export_rows(left_instance) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let right = match export_rows(right_instance) {
    Ok(value) => value
    Err(err) => return CliResult::failure(1, err.to_string())
  }
  let left_only = difference_count(left, right)
  let right_only = difference_count(right, left)
  let changed = left_only + right_only
  if invocation.json {
    CliResult::success(
      "{\"leftFacts\":" +
      left.length().to_string() +
      ",\"rightFacts\":" +
      right.length().to_string() +
      ",\"leftOnly\":" +
      left_only.to_string() +
      ",\"rightOnly\":" +
      right_only.to_string() +
      ",\"changed\":" +
      changed.to_string() +
      "}",
    )
  } else {
    CliResult::success(
      "left_facts: " +
      left.length().to_string() +
      "\nright_facts: " +
      right.length().to_string() +
      "\nleft_only: " +
      left_only.to_string() +
      "\nright_only: " +
      right_only.to_string() +
      "\nchanged: " +
      changed.to_string(),
    )
  }
}

///|
pub fn run(args : ArrayView[String]) -> CliResult {
  let invocation = match parse_invocation(args) {
    Ok(value) => value
    Err(err) =>
      return CliResult::failure(
        2,
        "xbrlens: " + err.to_string() + "\n\n" + cli_help_text(),
      )
  }
  if invocation.help {
    return CliResult::success(cli_help_text())
  }
  match invocation.command {
    Help => CliResult::success(cli_help_text())
    Version => CliResult::success("xbrlens " + version())
    Inspect => run_inspect(invocation)
    Facts => run_facts(invocation)
    Validate => run_validate(invocation)
    Calc => run_calc(invocation)
    Diff => run_diff(invocation)
  }
}

///|
pub extend CliCommand with Eq::{not_equal, equal}

///|
pub extend CliCommand with @debug.Debug::{to_repr}

///|
pub extend CliInvocation with Eq::{not_equal, equal}

///|
pub extend CliInvocation with @debug.Debug::{to_repr}

///|
pub extend CliError with Eq::{not_equal, equal}

///|
pub extend CliError with @debug.Debug::{to_repr}

///|
pub extend CliError with Show::{to_string, output}

///|
pub extend CliResult with Eq::{not_equal, equal}

///|
pub extend CliResult with @debug.Debug::{to_repr}
