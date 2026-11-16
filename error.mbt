///|
pub(all) enum XbrlError {
  InvalidLimit(String, Int32)
  LimitExceeded(String, Int32, Int32)
  InvalidQName(String, Int32)
  MissingNamespace(String, Int32)
  XmlSyntax(String, Int32)
  UnsafeXml(String, Int32)
  InvalidDecimal(String, Int32)
  InvalidContext(String, Int32)
  InvalidUnit(String, Int32)
  InvalidTaxonomy(String, Int32)
  MissingConcept(String)
  UnresolvedReference(String)
  InvalidDimension(String, Int32)
  DuplicateFact(String, Int32)
  CalculationMismatch(String, String, String)
  InvalidFact(String, Int32)
  UnsupportedFeature(String)
  Io(String)
} derive(Eq, @debug.Debug)

///|
pub impl Show for XbrlError with fn output(self, logger) {
  match self {
    InvalidLimit(name, value) =>
      logger.write_string("invalid limit " + name + ": " + value.to_string())
    LimitExceeded(name, maximum, actual) =>
      logger.write_string(
        name +
        " exceeds limit: maximum=" +
        maximum.to_string() +
        " actual=" +
        actual.to_string(),
      )
    InvalidQName(message, offset) =>
      logger.write_string(
        "invalid QName at offset " + offset.to_string() + ": " + message,
      )
    MissingNamespace(prefix, offset) =>
      logger.write_string(
        "unbound namespace prefix '" +
        prefix +
        "' at offset " +
        offset.to_string(),
      )
    XmlSyntax(message, offset) =>
      logger.write_string(
        "invalid XML at offset " + offset.to_string() + ": " + message,
      )
    UnsafeXml(message, offset) =>
      logger.write_string(
        "unsafe XML at offset " + offset.to_string() + ": " + message,
      )
    InvalidDecimal(message, offset) =>
      logger.write_string(
        "invalid decimal at offset " + offset.to_string() + ": " + message,
      )
    InvalidContext(message, offset) =>
      logger.write_string(
        "invalid context at offset " + offset.to_string() + ": " + message,
      )
    InvalidUnit(message, offset) =>
      logger.write_string(
        "invalid unit at offset " + offset.to_string() + ": " + message,
      )
    InvalidTaxonomy(message, offset) =>
      logger.write_string(
        "invalid taxonomy at offset " + offset.to_string() + ": " + message,
      )
    MissingConcept(name) => logger.write_string("missing concept: " + name)
    UnresolvedReference(value) =>
      logger.write_string("unresolved reference: " + value)
    InvalidDimension(message, offset) =>
      logger.write_string(
        "invalid dimension at offset " + offset.to_string() + ": " + message,
      )
    DuplicateFact(fact_id, offset) =>
      logger.write_string(
        "duplicate fact '" + fact_id + "' at offset " + offset.to_string(),
      )
    CalculationMismatch(role, concept, detail) =>
      logger.write_string(
        "calculation mismatch in role " +
        role +
        " for " +
        concept +
        ": " +
        detail,
      )
    InvalidFact(message, offset) =>
      logger.write_string(
        "invalid fact at offset " + offset.to_string() + ": " + message,
      )
    UnsupportedFeature(name) =>
      logger.write_string("unsupported feature: " + name)
    Io(message) => logger.write_string("I/O error: " + message)
  }
}

///|
pub extend XbrlError with Eq::{not_equal, equal}

///|
pub extend XbrlError with @debug.Debug::{to_repr}

///|
pub extend XbrlError with Show::{to_string, output}
