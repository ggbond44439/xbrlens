///|
fn main {
  let source = "<xbrli:xbrl xmlns:xbrli=\"http://www.xbrl.org/2003/instance\" xmlns:ex=\"urn:example\"><xbrli:context id=\"c\"><xbrli:entity><xbrli:identifier scheme=\"urn:test\">e</xbrli:identifier></xbrli:entity><xbrli:period><xbrli:instant>2024-12-31</xbrli:instant></xbrli:period></xbrli:context><ex:Value contextRef=\"c\">42</ex:Value></xbrli:xbrl>"
  let audit = match
    @xbrlens.audit_instance_source(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => abort(err.to_string())
  }
  println("facts=" + audit.facts.to_string())
  let instance = match
    @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
    Ok(value) => value
    Err(err) => abort(err.to_string())
  }
  let json = match @xbrlens.export_json(instance) {
    Ok(value) => value
    Err(err) => abort(err.to_string())
  }
  println(json)
}
