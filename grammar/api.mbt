///|
pub fn Grammar::new() -> Grammar {
  {
    start: None,
    rules: Map::new(),
    precedences: [],
    extras: [],
    externals: [],
    duplicate_rule_names: [],
    word: None,
    conflicts: [],
    supertypes: [],
  }
}

///|
pub fn Grammar::set_start(self : Grammar, name : String) -> Grammar {
  self.start = Some(name)
  self
}

///|
pub fn Grammar::add_rule(self : Grammar, rule : Rule) -> Grammar {
  if self.rules.contains(rule.name) {
    self.duplicate_rule_names.push(rule.name)
  }
  self.rules.set(rule.name, rule)
  self
}

///|
pub fn Grammar::add_extra(self : Grammar, pattern : Pattern) -> Grammar {
  self.extras.push(pattern)
  self
}

///|
pub fn Grammar::add_external(self : Grammar, name : String) -> Grammar {
  self.externals.push(name)
  self
}

///|
pub fn Grammar::set_word(self : Grammar, name : String) -> Grammar {
  self.word = Some(name)
  self
}

///|
pub fn Grammar::add_conflict(self : Grammar, group : Array[String]) -> Grammar {
  self.conflicts.push(group)
  self
}

///|
pub fn Grammar::add_supertype(self : Grammar, name : String) -> Grammar {
  self.supertypes.push(name)
  self
}

///|
pub fn Grammar::add_precedence(
  self : Grammar,
  kind : PrecKind,
  rules : Array[String],
) -> Grammar {
  let level = self.precedences.length() + 1
  self.precedences.push({ level, kind, rules })
  self
}

// Rule builder

///|
pub fn Rule::new(name : String, pattern : Pattern) -> Rule {
  let is_named = !name.has_prefix("_")
  {
    name,
    pattern,
    is_named,
    is_token: false,
    params: [],
    attributes: [],
    location: None,
  }
}

///|
pub fn Rule::token(name : String, pattern : Pattern) -> Rule {
  let is_named = !name.has_prefix("_")
  {
    name,
    pattern,
    is_named,
    is_token: true,
    params: [],
    attributes: [],
    location: None,
  }
}

///|
pub fn Rule::template(
  name : String,
  params : Array[String],
  pattern : Pattern,
) -> Rule {
  let is_named = !name.has_prefix("_")
  {
    name,
    pattern,
    is_named,
    is_token: false,
    params,
    attributes: [],
    location: None,
  }
}

///|
pub fn Rule::with_attribute(self : Rule, attr : RuleAttribute) -> Rule {
  let new_attrs = self.attributes.copy()
  new_attrs.push(attr)
  { ..self, attributes: new_attrs }
}

// Pattern combinators

///|
pub fn seq(patterns : Array[Pattern]) -> Pattern {
  Pattern::Seq(patterns)
}

///|
pub fn choice(patterns : Array[Pattern]) -> Pattern {
  Pattern::Choice(patterns)
}

///|
pub fn lit(s : String) -> Pattern {
  Pattern::Literal(s)
}

///|
pub fn re(s : String) -> Pattern {
  Pattern::Regex(s)
}

///|
pub fn ref_(name : String) -> Pattern {
  Pattern::RuleRef(name)
}

///|
pub fn repeat(p : Pattern) -> Pattern {
  Pattern::Repeat(p)
}

///|
pub fn plus(p : Pattern) -> Pattern {
  Pattern::Plus(p)
}

///|
pub fn optional(p : Pattern) -> Pattern {
  Pattern::Optional(p)
}

///|
pub fn field(name : String, p : Pattern) -> Pattern {
  Pattern::Field(name, p)
}

///|
pub fn tagged(label : String, p : Pattern) -> Pattern {
  Pattern::Tagged(label, p)
}

///|
pub fn not_(p : Pattern) -> Pattern {
  Pattern::Not(p)
}

///|
pub fn and_(p : Pattern) -> Pattern {
  Pattern::And(p)
}

///|
pub fn repeat_exact(p : Pattern, n : Int) -> Pattern {
  Pattern::RepeatRange(p, n, n)
}

///|
pub fn repeat_range(p : Pattern, min : Int, max : Int) -> Pattern {
  Pattern::RepeatRange(p, min, max)
}

///|
pub fn prec(level : Int, kind : PrecKind, p : Pattern) -> Pattern {
  Pattern::Prec(level, kind, p)
}

///|
pub fn alias_(name : String, p : Pattern) -> Pattern {
  Pattern::Alias(name, p)
}

///|
pub fn app(rule_name : String, args : Array[Pattern]) -> Pattern {
  Pattern::RuleApp(rule_name, args)
}
