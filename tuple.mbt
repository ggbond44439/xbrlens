///|
pub(all) struct XbrlTuple {
  id : String?
  concept : QName
  facts : Array[XbrlFact]
  tuples : Array[XbrlTuple]
  offset : Int32
} derive(Eq, @debug.Debug)

///|
priv enum ParsedExtensionNode {
  ItemNode(XbrlFact)
  TupleNode(XbrlTuple)
}

///|
fn claim_extension_id(node : XmlNode, ids : Array[String]) -> Result[Unit, XbrlError] {
  match node.attribute("", "id") {
    Some(id) if id.trim().length() > 0 => {
      for existing in ids {
        if existing == id {
          return Err(DuplicateFact(id, node.offset))
        }
      }
      ids.push(id)
      Ok(())
    }
    _ => Ok(())
  }
}

///|
fn validate_item_references(
  fact : XbrlFact,
  contexts : Array[XbrlContext],
  units : Array[XbrlUnitDefinition],
) -> Result[Unit, XbrlError] {
  let mut context_found = false
  for context in contexts {
    if context.id == fact.context_ref {
      context_found = true
      break
    }
  }
  if !context_found {
    return Err(UnresolvedReference("context '" + fact.context_ref + "'"))
  }
  match fact.unit_ref {
    Some(unit_id) => {
      let mut unit_found = false
      for unit in units {
        if unit.id == unit_id {
          unit_found = true
          break
        }
      }
      if !unit_found {
        return Err(UnresolvedReference("unit '" + unit_id + "'"))
      }
    }
    None => ()
  }
  Ok(())
}

///|
fn parse_extension_node(
  node : XmlNode,
  contexts : Array[XbrlContext],
  units : Array[XbrlUnitDefinition],
  ids : Array[String],
  limits : XbrlLimits,
  fact_count : Array[Int32],
) -> Result[ParsedExtensionNode, XbrlError] {
  match claim_extension_id(node, ids) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  if required_unqualified_attribute(node, "contextRef") is Some(_) {
    let fact = match parse_fact(node) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    match validate_item_references(fact, contexts, units) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    fact_count[0] += 1
    match limits.check_facts(fact_count[0]) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    Ok(ItemNode(fact))
  } else {
    if node.text.trim().length() > 0 {
      return Err(InvalidFact("tuple cannot contain direct text", node.offset))
    }
    let facts : Array[XbrlFact] = []
    let tuples : Array[XbrlTuple] = []
    for child in node.children {
      let parsed = match parse_extension_node(
        child,
        contexts,
        units,
        ids,
        limits,
        fact_count,
      ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match parsed {
        ItemNode(fact) => facts.push(fact)
        TupleNode(tuple) => tuples.push(tuple)
      }
    }
    Ok(TupleNode({
      id: node.attribute("", "id"),
      concept: node.name,
      facts,
      tuples,
      offset: node.offset,
    }))
  }
}

///|
pub fn parse_extension_nodes(
  nodes : Array[XmlNode],
  contexts : Array[XbrlContext],
  units : Array[XbrlUnitDefinition],
  limits : XbrlLimits,
) -> Result[(Array[XbrlFact], Array[XbrlTuple]), XbrlError] {
  let facts : Array[XbrlFact] = []
  let tuples : Array[XbrlTuple] = []
  let ids : Array[String] = []
  let fact_count : Array[Int32] = [0]
  for node in nodes {
    let parsed = match parse_extension_node(
      node,
      contexts,
      units,
      ids,
      limits,
      fact_count,
    ) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    match parsed {
      ItemNode(fact) => facts.push(fact)
      TupleNode(tuple) => tuples.push(tuple)
    }
  }
  Ok((facts, tuples))
}

///|
pub extend XbrlTuple with Eq::{not_equal, equal}

///|
pub extend XbrlTuple with @debug.Debug::{to_repr}
