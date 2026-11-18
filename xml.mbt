///|
pub(all) struct XmlAttribute {
  name : QName
  value : String
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct XmlNode {
  name : QName
  attributes : Array[XmlAttribute]
  namespaces : Array[NamespaceBinding]
  children : Array[XmlNode]
  text : String
  offset : Int32
} derive(Eq, @debug.Debug)

///|
pub(all) struct XmlDocument {
  root : XmlNode
} derive(Eq, @debug.Debug)

///|
pub fn XmlNode::attribute(
  self : XmlNode,
  namespace_uri : String,
  local_name : String,
) -> String? {
  for attribute in self.attributes {
    if attribute.name.matches(namespace_uri, local_name) {
      return Some(attribute.value)
    }
  }
  None
}

///|
pub fn XmlNode::attribute_by_local(
  self : XmlNode,
  local_name : String,
) -> String? {
  for attribute in self.attributes {
    if attribute.name.local_name == local_name {
      return Some(attribute.value)
    }
  }
  None
}

///|
pub fn XmlNode::child(
  self : XmlNode,
  namespace_uri : String,
  local_name : String,
) -> XmlNode? {
  for child in self.children {
    if child.name.matches(namespace_uri, local_name) {
      return Some(child)
    }
  }
  None
}

///|
pub fn XmlNode::children_named(
  self : XmlNode,
  namespace_uri : String,
  local_name : String,
) -> Array[XmlNode] {
  let result : Array[XmlNode] = []
  for child in self.children {
    if child.name.matches(namespace_uri, local_name) {
      result.push(child)
    }
  }
  result
}

///|
priv struct RawAttribute {
  lexical_name : String
  value : String
  offset : Int32
}

///|
priv struct StartTag {
  name : QName
  attributes : Array[XmlAttribute]
  namespaces : Array[NamespaceBinding]
  self_closing : Bool
  offset : Int32
}

///|
priv struct XmlParser {
  source : StringView
  mut index : Int32
  limits : XbrlLimits
  mut node_count : Int32
  mut text_bytes : Int32
}

///|
fn XmlParser::new(source : StringView, limits : XbrlLimits) -> XmlParser {
  { source, index: 0, limits, node_count: 0, text_bytes: 0, }
}

///|
fn is_xml_space(code : UInt16) -> Bool {
  code == 32 || code == 9 || code == 10 || code == 13
}

///|
fn is_name_delimiter(code : UInt16) -> Bool {
  is_xml_space(code) ||
  code == 47 ||
  code == 62 ||
  code == 61 ||
  code == 60 ||
  code == 63
}

///|
fn XmlParser::starts_with(self : XmlParser, value : String) -> Bool {
  let length = value.length()
  if self.index + length > self.source.length() {
    return false
  }
  let mut offset = 0
  while offset < length {
    if self.source.at(self.index + offset) != value.code_units()[offset] {
      return false
    }
    offset += 1
  }
  true
}

///|
fn XmlParser::skip_space(self : XmlParser) -> Unit {
  while self.index < self.source.length() &&
        is_xml_space(self.source.at(self.index)) {
    self.index += 1
  }
}

///|
fn XmlParser::consume(
  self : XmlParser,
  value : String,
) -> Result[Unit, XbrlError] {
  if !self.starts_with(value) {
    return Err(XmlSyntax("expected '" + value + "'", self.index))
  }
  self.index += value.length()
  Ok(())
}

///|
fn XmlParser::skip_until(
  self : XmlParser,
  terminator : String,
  feature : String,
) -> Result[Unit, XbrlError] {
  let start = self.index
  while self.index + terminator.length() <= self.source.length() {
    if self.starts_with(terminator) {
      self.index += terminator.length()
      return Ok(())
    }
    self.index += 1
  }
  Err(XmlSyntax("unterminated " + feature, start))
}

///|
fn XmlParser::skip_misc(self : XmlParser) -> Result[Unit, XbrlError] {
  let mut progress = true
  while progress {
    progress = false
    self.skip_space()
    if self.starts_with("<!--") {
      self.index += 4
      match self.skip_until("-->", "comment") {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      progress = true
    } else if self.starts_with("<?xml") {
      return Err(
        XmlSyntax(
          "XML declaration is only allowed at the document start",
          self.index,
        ),
      )
    } else if self.starts_with("<?") {
      self.index += 2
      match self.skip_until("?>", "processing instruction") {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      progress = true
    }
  }
  Ok(())
}

///|
fn XmlParser::parse_name(self : XmlParser) -> Result[String, XbrlError] {
  let start = self.index
  while self.index < self.source.length() &&
        !is_name_delimiter(self.source.at(self.index)) {
    self.index += 1
  }
  if self.index == start {
    return Err(XmlSyntax("expected XML name", start))
  }
  Ok(self.source.view(start_offset=start, end_offset=self.index).to_owned())
}

///|
fn parse_decimal_digits(
  source : StringView,
  start : Int32,
  end : Int32,
  radix : Int32,
) -> Result[Int32, XbrlError] {
  if start >= end {
    return Err(XmlSyntax("empty character reference", start))
  }
  let mut value : Int32 = 0
  let mut index = start
  while index < end {
    let code = source.at(index).to_int()
    let digit = if code >= 48 && code <= 57 {
      code - 48
    } else if radix == 16 && code >= 65 && code <= 70 {
      code - 55
    } else if radix == 16 && code >= 97 && code <= 102 {
      code - 87
    } else {
      return Err(XmlSyntax("invalid character reference digit", index))
    }
    if value > (1_114_111 - digit) / radix {
      return Err(XmlSyntax("character reference is out of range", start))
    }
    value = value * radix + digit
    index += 1
  }
  Ok(value)
}

///|
fn invalid_xml_char(code : UInt16) -> Bool {
  code == 0 ||
  (code < 32 && code != 9 && code != 10 && code != 13) ||
  code == 65534 ||
  code == 65535
}

///|
fn validate_xml_segment(
  value : StringView,
  offset : Int32,
) -> Result[Unit, XbrlError] {
  let mut index = 0
  while index < value.length() {
    if invalid_xml_char(value.at(index)) {
      return Err(XmlSyntax("invalid XML control character", offset + index))
    }
    index += 1
  }
  Ok(())
}

///|
fn append_codepoint(
  builder : StringBuilder,
  value : Int32,
  offset : Int32,
) -> Result[Unit, XbrlError] {
  if value == 0 || value > 1_114_111 || (value >= 55_296 && value <= 57_343) {
    return Err(XmlSyntax("invalid XML code point", offset))
  }
  builder.write_string(value.unsafe_to_char().to_string())
  Ok(())
}

///|
fn decode_xml_text(
  value : StringView,
  offset : Int32,
) -> Result[String, XbrlError] {
  let builder = StringBuilder()
  let mut index = 0
  let length = value.length()
  while index < length {
    if value.at(index) != 38 {
      if invalid_xml_char(value.at(index)) {
        return Err(XmlSyntax("invalid XML control character", offset + index))
      }
      builder.write_string(
        value.view(start_offset=index, end_offset=index + 1).to_owned(),
      )
      index += 1
      continue
    }
    let entity_start = index
    index += 1
    let content_start = index
    while index < length && value.at(index) != 59 {
      index += 1
    }
    if index >= length {
      return Err(
        XmlSyntax("unterminated entity reference", offset + entity_start),
      )
    }
    let content = value.view(start_offset=content_start, end_offset=index)
    if content == "amp" {
      builder.write_string("&")
    } else if content == "lt" {
      builder.write_string("<")
    } else if content == "gt" {
      builder.write_string(">")
    } else if content == "quot" {
      builder.write_string("\"")
    } else if content == "apos" {
      builder.write_string("'")
    } else if content.length() > 1 && content.at(0) == 35 {
      let hex = content.length() > 2 &&
        (content.at(1) == 120 || content.at(1) == 88)
      let digits_start = if hex { 2 } else { 1 }
      let code = match
        parse_decimal_digits(
          content,
          digits_start,
          content.length(),
          if hex {
            16
          } else {
            10
          },
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match append_codepoint(builder, code, offset + entity_start) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    } else {
      return Err(
        XmlSyntax(
          "unknown entity '&" + content.to_owned() + ";'",
          offset + entity_start,
        ),
      )
    }
    index += 1
  }
  Ok(builder.to_string())
}

///|
fn XmlParser::parse_attribute_value(
  self : XmlParser,
) -> Result[String, XbrlError] {
  if self.index >= self.source.length() ||
    (self.source.at(self.index) != 34 && self.source.at(self.index) != 39) {
    return Err(XmlSyntax("expected quoted attribute value", self.index))
  }
  let quote = self.source.at(self.index)
  self.index += 1
  let start = self.index
  while self.index < self.source.length() && self.source.at(self.index) != quote {
    if self.source.at(self.index) == 60 {
      return Err(
        XmlSyntax("'<' is not allowed in attribute values", self.index),
      )
    }
    self.index += 1
  }
  if self.index >= self.source.length() {
    return Err(XmlSyntax("unterminated attribute value", start))
  }
  let raw = self.source.view(start_offset=start, end_offset=self.index)
  self.index += 1
  decode_xml_text(raw, start)
}

///|
fn add_namespace_binding(
  bindings : Array[NamespaceBinding],
  prefix : String,
  uri : String,
  offset : Int32,
) -> Result[Unit, XbrlError] {
  if prefix == "xmlns" {
    return Err(XmlSyntax("the xmlns prefix cannot be redeclared", offset))
  }
  if uri == "http://www.w3.org/2000/xmlns/" {
    return Err(XmlSyntax("the XMLNS namespace URI is reserved", offset))
  }
  if prefix == "xml" && uri != "http://www.w3.org/XML/1998/namespace" {
    return Err(XmlSyntax("the xml prefix must use the XML namespace", offset))
  }
  if prefix != "" && uri == "" {
    return Err(
      XmlSyntax("a namespace prefix cannot be bound to an empty URI", offset),
    )
  }
  if prefix == "" && uri == "http://www.w3.org/XML/1998/namespace" {
    return Err(
      XmlSyntax("the XML namespace cannot be the default namespace", offset),
    )
  }
  bindings.push({ prefix, uri, })
  Ok(())
}

///|
fn namespace_bindings(
  parent : Array[NamespaceBinding],
  raw : Array[RawAttribute],
) -> Result[Array[NamespaceBinding], XbrlError] {
  let bindings : Array[NamespaceBinding] = []
  for item in parent {
    bindings.push(item)
  }
  for attribute in raw {
    if attribute.lexical_name == "xmlns" {
      match
        add_namespace_binding(bindings, "", attribute.value, attribute.offset) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    } else if attribute.lexical_name.has_prefix("xmlns:") {
      let prefix = attribute.lexical_name.view(start_offset=6).to_owned()
      if prefix == "" {
        return Err(XmlSyntax("empty namespace prefix", attribute.offset))
      }
      match
        add_namespace_binding(
          bindings,
          prefix,
          attribute.value,
          attribute.offset,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
  }
  Ok(bindings)
}

///|
fn has_expanded_attribute(
  attributes : Array[XmlAttribute],
  name : QName,
) -> Bool {
  for attribute in attributes {
    if attribute.name == name {
      return true
    }
  }
  false
}

///|
fn XmlParser::parse_start_tag(
  self : XmlParser,
  parent_bindings : Array[NamespaceBinding],
) -> Result[StartTag, XbrlError] {
  let start = self.index
  match self.consume("<") {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let lexical_name = match self.parse_name() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let raw_attributes : Array[RawAttribute] = []
  let mut self_closing = false
  while true {
    self.skip_space()
    if self.starts_with("/>") {
      self.index += 2
      self_closing = true
      break
    }
    if self.starts_with(">") {
      self.index += 1
      break
    }
    let attribute_offset = self.index
    let attribute_name = match self.parse_name() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    self.skip_space()
    match self.consume("=") {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    self.skip_space()
    let value = match self.parse_attribute_value() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    for previous in raw_attributes {
      if previous.lexical_name == attribute_name {
        return Err(
          XmlSyntax(
            "duplicate attribute '" + attribute_name + "'",
            attribute_offset,
          ),
        )
      }
    }
    raw_attributes.push({
      lexical_name: attribute_name,
      value,
      offset: attribute_offset,
    })
  }
  match self.limits.check_attributes(raw_attributes.length()) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let bindings = match namespace_bindings(parent_bindings, raw_attributes) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let name = match resolve_qname(lexical_name, bindings, true) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let attributes : Array[XmlAttribute] = []
  for raw in raw_attributes {
    if raw.lexical_name != "xmlns" && !raw.lexical_name.has_prefix("xmlns:") {
      let expanded = match resolve_qname(raw.lexical_name, bindings, false) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if has_expanded_attribute(attributes, expanded) {
        return Err(
          XmlSyntax(
            "duplicate expanded attribute '" + expanded.expanded() + "'",
            raw.offset,
          ),
        )
      }
      attributes.push({ name: expanded, value: raw.value, offset: raw.offset, })
    }
  }
  Ok({ name, attributes, namespaces: bindings, self_closing, offset: start, })
}

///|
fn XmlParser::parse_element(
  self : XmlParser,
  parent_bindings : Array[NamespaceBinding],
  depth : Int32,
) -> Result[XmlNode, XbrlError] {
  match self.limits.check_depth(depth) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  self.node_count += 1
  match self.limits.check_nodes(self.node_count) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let tag = match self.parse_start_tag(parent_bindings) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag.self_closing {
    return Ok({
      name: tag.name,
      attributes: tag.attributes,
      namespaces: tag.namespaces,
      children: [],
      text: "",
      offset: tag.offset,
    })
  }
  let children : Array[XmlNode] = []
  let text = StringBuilder()
  while self.index < self.source.length() {
    if self.starts_with("</") {
      self.index += 2
      let closing = match self.parse_name() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let closing_name = match resolve_qname(closing, tag.namespaces, true) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if closing_name != tag.name {
        return Err(
          XmlSyntax("mismatched closing element '" + closing + "'", self.index),
        )
      }
      self.skip_space()
      match self.consume(">") {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      return Ok({
        name: tag.name,
        attributes: tag.attributes,
        namespaces: tag.namespaces,
        children,
        text: text.to_string(),
        offset: tag.offset,
      })
    } else if self.starts_with("<!--") {
      self.index += 4
      match self.skip_until("-->", "comment") {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    } else if self.starts_with("<![CDATA[") {
      self.index += 9
      let start = self.index
      while self.index + 3 <= self.source.length() && !self.starts_with("]]>") {
        self.index += 1
      }
      if self.index + 3 > self.source.length() {
        return Err(XmlSyntax("unterminated CDATA section", start))
      }
      let cdata_view = self.source.view(
        start_offset=start,
        end_offset=self.index,
      )
      match validate_xml_segment(cdata_view, start) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let cdata = cdata_view.to_owned()
      self.text_bytes += cdata.length()
      match self.limits.check_text(self.text_bytes) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      text.write_string(cdata)
      self.index += 3
    } else if self.starts_with("<?") {
      if self.starts_with("<?xml") {
        return Err(
          XmlSyntax(
            "XML declaration is only allowed at the document start",
            self.index,
          ),
        )
      }
      self.index += 2
      match self.skip_until("?>", "processing instruction") {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    } else if self.starts_with("<!") {
      return Err(
        UnsafeXml("DOCTYPE and declarations are not allowed", self.index),
      )
    } else if self.starts_with("<") {
      let child = match self.parse_element(tag.namespaces, depth + 1) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      children.push(child)
    } else {
      let start = self.index
      while self.index < self.source.length() &&
            self.source.at(self.index) != 60 {
        self.index += 1
      }
      let raw = self.source.view(start_offset=start, end_offset=self.index)
      let decoded = match decode_xml_text(raw, start) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if decoded.contains("]]>") {
        return Err(XmlSyntax("']]>' is not allowed in character data", start))
      }
      self.text_bytes += decoded.length()
      match self.limits.check_text(self.text_bytes) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      text.write_string(decoded)
    }
  }
  Err(
    XmlSyntax("unterminated element '" + tag.name.expanded() + "'", tag.offset),
  )
}

///|
pub fn parse_xml(
  source : StringView,
  limits : XbrlLimits,
) -> Result[XmlDocument, XbrlError] {
  match limits.validate() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  match limits.check_source(source.length()) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  match validate_xml_segment(source, 0) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let parser = XmlParser::new(source, limits)
  if parser.source.length() > 0 && parser.source.at(0) == 0xFEFF {
    parser.index = 1
  }
  if parser.starts_with("<?xml") {
    match parser.skip_until("?>", "XML declaration") {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  match parser.skip_misc() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  if parser.starts_with("<!") {
    return Err(
      UnsafeXml("DOCTYPE and declarations are not allowed", parser.index),
    )
  }
  if parser.index >= parser.source.length() ||
    parser.source.at(parser.index) != 60 {
    return Err(XmlSyntax("expected root element", parser.index))
  }
  let root = match parser.parse_element([], 1) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match parser.skip_misc() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  if parser.index != parser.source.length() {
    return Err(XmlSyntax("trailing content after root element", parser.index))
  }
  Ok({ root, })
}

///|
pub extend XmlAttribute with Eq::{not_equal, equal}

///|
pub extend XmlAttribute with @debug.Debug::{to_repr}

///|
pub extend XmlNode with Eq::{not_equal, equal}

///|
pub extend XmlNode with @debug.Debug::{to_repr}

///|
pub extend XmlDocument with Eq::{not_equal, equal}

///|
pub extend XmlDocument with @debug.Debug::{to_repr}
