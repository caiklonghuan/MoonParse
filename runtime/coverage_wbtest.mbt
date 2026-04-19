///|
// coverage_wbtest.mbt — 语法覆盖率报告（Phase 3.1）

///|
fn coverage_table(dsl : String) -> @tablegen.ParseTable {
  match @grammar.parse_grammar(dsl) {
    @grammar.Error(e) => {
      println(e.message)
      panic()
    }
    @grammar.Success(g) =>
      match @tablegen.generate_parse_table(g) {
        Err(e) => {
          println(e)
          panic()
        }
        Ok((table, _)) => table
      }
  }
}

///|
test "grammar coverage / 未命中与低命中 production 报告" {
  let dsl =
    #|start stmt
    #|extras [/[ \t\n\r]+/]
    #|rule stmt: assign | if_stmt
    #|rule assign: ident "=" value ";"
    #|rule if_stmt: "if" expr "then" stmt "else" stmt | "if" expr "then" stmt
    #|rule expr: ident | value
    #|rule value: number | string
    #|rule ident: /[a-z]+/
    #|rule number: /[0-9]+/
    #|rule string: /\"[a-z]+\"/
  let table = coverage_table(dsl)
  let report = grammar_coverage_report(table, ["x = 1;", "if x then y = 2;"], 1)
  inspect(
    report,
    content=(
      #|inputs=2 parse_failures=0 low_hit_threshold=1
      #|recovery error_nodes=0 missing_nodes=0 total=0
      #|rule_hits:
      #|  $accept = 0
      #|  stmt = 3
      #|  assign = 2
      #|  if_stmt = 1
      #|  expr = 1
      #|  value = 2
      #|  ident = 3
      #|  number = 2
      #|  string = 0
      #|unhit_rules:
      #|  $accept
      #|  string
      #|branch_hits:
      #|  $accept#0 -> stmt $ = 0
      #|  stmt#0 -> assign = 2
      #|  stmt#1 -> if_stmt = 1
      #|  assign#0 -> ident lit:= value lit:; = 2
      #|  if_stmt#0 -> lit:if expr lit:then stmt lit:else stmt = 0
      #|  if_stmt#1 -> lit:if expr lit:then stmt = 1
      #|  expr#0 -> ident = 1
      #|  expr#1 -> value = 0
      #|  value#0 -> number = 2
      #|  value#1 -> string = 0
      #|  ident#0 -> re:[a-z]+ = 3
      #|  number#0 -> re:[0-9]+ = 2
      #|  string#0 -> re:\"[a-z]+\" = 0
      #|production_hits:
      #|  [0] $accept -> stmt $ = 0
      #|  [1] stmt -> assign = 2
      #|  [2] stmt -> if_stmt = 1
      #|  [3] assign -> ident lit:= value lit:; = 2
      #|  [4] if_stmt -> lit:if expr lit:then stmt lit:else stmt = 0
      #|  [5] if_stmt -> lit:if expr lit:then stmt = 1
      #|  [6] expr -> ident = 1
      #|  [7] expr -> value = 0
      #|  [8] value -> number = 2
      #|  [9] value -> string = 0
      #|  [10] ident -> re:[a-z]+ = 3
      #|  [11] number -> re:[0-9]+ = 2
      #|  [12] string -> re:\"[a-z]+\" = 0
      #|unhit_productions:
      #|  [0] $accept -> stmt $
      #|  [4] if_stmt -> lit:if expr lit:then stmt lit:else stmt
      #|  [7] expr -> value
      #|  [9] value -> string
      #|  [12] string -> re:\"[a-z]+\"
      #|low_hit_productions:
      #|  [2] stmt -> if_stmt = 1
      #|  [5] if_stmt -> lit:if expr lit:then stmt = 1
      #|  [6] expr -> ident = 1
      #|token_hits:
      #|  [1] lit:; = 2
      #|  [2] lit:if = 1
      #|  [3] lit:then = 1
      #|  [4] lit:else = 0
      #|  [5] re:[a-z]+ = 3
      #|  [6] re:[0-9]+ = 2
      #|  [7] re:\"[a-z]+\" = 0
      #|  [8] re:[ \t\n\r]+ = 7
      #|unhit_tokens:
      #|  [4] lit:else
      #|  [7] re:\"[a-z]+\"
      #|
    ),
  )
}

///|
test "grammar coverage / error recovery 路径命中报告" {
  let table = coverage_table("start s\nrule s: \"a\" \";\" \"b\"")
  let report = grammar_coverage_report(table, ["!ab"], 1)
  inspect(
    report,
    content=(
      #|inputs=1 parse_failures=0 low_hit_threshold=1
      #|recovery error_nodes=1 missing_nodes=1 total=2
      #|rule_hits:
      #|  $accept = 1
      #|  s = 1
      #|unhit_rules:
      #|branch_hits:
      #|  $accept#0 -> s $ = 1
      #|  s#0 -> lit:a lit:; lit:b = 1
      #|production_hits:
      #|  [0] $accept -> s $ = 1
      #|  [1] s -> lit:a lit:; lit:b = 1
      #|unhit_productions:
      #|low_hit_productions:
      #|  [0] $accept -> s $ = 1
      #|  [1] s -> lit:a lit:; lit:b = 1
      #|token_hits:
      #|  [1] lit:; = 1
      #|  [2] lit:b = 1
      #|unhit_tokens:
      #|
    ),
  )
}
