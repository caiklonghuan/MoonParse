///|
fn parse_python_ok(source : String) -> @runtime.CstNode {
  match @grammars.parse_python(source) {
    Ok(node) => node
    Err(e) => {
      println("parse_python failed: \{e.message}")
      panic()
    }
  }
}

///|
fn nested_python_list(depth : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("data = ")
  for _ in 0..<depth {
    buf.write_char('[')
  }
  buf.write_string("0")
  for _ in 0..<depth {
    buf.write_char(']')
  }
  buf.to_string()
}

///|
fn nested_python_dict(depth : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("data = ")
  for i in 0..<depth {
    buf.write_string("{'k")
    buf.write_string(i.to_string())
    buf.write_string("': ")
  }
  buf.write_string("0")
  for _ in 0..<depth {
    buf.write_char('}')
  }
  buf.to_string()
}

///|
fn wide_python_module(
  param_count : Int,
  field_count : Int,
  statement_count : Int,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("def wide(")
  for i in 0..<param_count {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string("a")
    buf.write_string(i.to_string())
  }
  buf.write_string("):\n    return a0\n")
  buf.write_string("config = {")
  for i in 0..<field_count {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string("'k")
    buf.write_string(i.to_string())
    buf.write_string("': ")
    buf.write_string(i.to_string())
  }
  buf.write_string("}\n")
  for i in 0..<statement_count {
    buf.write_string("x")
    buf.write_string(i.to_string())
    buf.write_string(" = ")
    buf.write_string(i.to_string())
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
test "python_nested_if_in_function" {
  let source =
    #|def fib(n):
    #|    if n <= 1:
    #|        return n
    #|    return fib(n - 1) + fib(n - 2)
    #|fib(10)
    #|
    #|def demo37(a, b):
    #|  dout1 = a + b
    #|  dout2 = a * b
    #|  return dout1, dout2
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_class_with_method" {
  let source =
    #|class Point:
    #|    def x(self):
    #|        return 1
    #|    def y(self):
    #|        return 2
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_inline_for_loop" {
  let source =
    #|for value in [1, 4, 9]: print(value)
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_type_annotations" {
  let source =
    #|def area(r: float) -> float:
    #|    return 3.14 * r * r
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_from_import" {
  let source =
    #|from typing import List
    #|from math import pi, sqrt
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_dict_literal" {
  let source =
    #|config = {'host': 'localhost', 'port': 5432}
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_while_and_break" {
  let source =
    #|def find(xs, target):
    #|    i = 0
    #|    while i < 10:
    #|        if xs == target:
    #|            break
    #|        i = i + 1
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_lambda_expression" {
  let source =
    #|f = lambda x: x * x
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 1.4  最小结构 snapshot 集
// ============================================================

///|
test "python snapshot / 赋值语句" {
  inspect(
    @grammars.python_sexp("x = 1"),
    content=(
      #|(module (EOF) (statement (simple_statement (assign_statement (target (identifier)) (expression (conditional_expression (or_expression (and_expression (not_expression (comparison_expression (bitwise_or_expression (bitwise_xor_expression (bitwise_and_expression (shift_expression (additive_expression (multiplicative_expression (power_expression (unary_expression (postfix_expression (primary_expression (literal (number_literal))))))))))))))))))))))
    ),
  )
}

///|
test "python snapshot / def 函数" {
  inspect(
    @grammars.python_sexp("def f(x):\n    return x"),
    content=(
      #|(module (EOF) (statement (compound_statement (decorated_statement (def_statement (identifier) (parameter_list (parameter_item (identifier))) (suite (statement (simple_statement (return_statement (expression_list (expression (conditional_expression (or_expression (and_expression (not_expression (comparison_expression (bitwise_or_expression (bitwise_xor_expression (bitwise_and_expression (shift_expression (additive_expression (multiplicative_expression (power_expression (unary_expression (postfix_expression (primary_expression (identifier)))))))))))))))))))))))))))
    ),
  )
}

///|
test "python snapshot / import" {
  inspect(
    @grammars.python_sexp("import os"),
    content=(
      #|(module (EOF) (statement (simple_statement (import_statement (import_alias (dotted_name (identifier)))))))
    ),
  )
}

///|
test "python_augmented_assign" {
  let source =
    #|x = 0
    #|x += 1
    #|x -= 2
    #|x *= 3
    #|x //= 4
    #|x **= 2
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_raise" {
  let source =
    #|raise ValueError("bad input")
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_global_del_assert" {
  let source =
    #|global x
    #|del x
    #|assert x == 1, "x must be 1"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_try_except_finally" {
  let source =
    #|try:
    #|    x = 1
    #|except ValueError:
    #|    x = 0
    #|finally:
    #|    done = True
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_try_except_as" {
  let source =
    #|try:
    #|    result = int("abc")
    #|except ValueError as e:
    #|    result = 0
    #|except Exception as e:
    #|    result = -1
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_with_statement" {
  let source =
    #|with open("data.txt") as f: pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_async_def" {
  let source =
    #|async def fetch(url): pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_star_kwargs_params" {
  let source =
    #|def f(*args, **kwargs): pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_keyword_arg_call" {
  let source =
    #|f(x=1, y=2)
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_splat_in_call" {
  let source =
    #|f(*args, **kwargs)
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_comparison_is_not_in" {
  let source =
    #|a = x is None
    #|b = x is not None
    #|c = x not in [1, 2, 3]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_for_tuple_target" {
  let source =
    #|for x, y in pairs: pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python stress / 100 层列表与字典嵌套" {
  let inputs = [nested_python_list(100), nested_python_dict(100)]
  for input in inputs {
    let root = parse_python_ok(input)
    assert_true(!@grammars.python_sexp(input).contains("ERROR"))
    assert_true(root.start_byte <= root.end_byte)
  }
}

///|
test "python stress / 超长参数列表、对象字段列表与连续 statement" {
  let input = wide_python_module(128, 128, 192)
  let root = parse_python_ok(input)
  assert_true(!@grammars.python_sexp(input).contains("ERROR"))
  assert_true(root.start_byte <= root.end_byte)
}

///|
test "python_list_comprehension" {
  let source =
    #|squares = [x * x for x in range(10)]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_list_comp_with_filter" {
  let source =
    #|evens = [x for x in range(20) if x % 2 == 0]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_nested_comprehension" {
  let source =
    #|flat = [x for row in matrix for x in row]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_dict_comprehension" {
  let source =
    #|d = {k: v for k, v in items.items()}
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_set_comprehension" {
  let source =
    #|s = {x * 2 for x in range(5)}
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 2.1  装饰器 (decorators)
// ============================================================

///|
test "python_decorator_simple" {
  let source = "@staticmethod\ndef f(): pass"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_decorator_with_args" {
  let source = "@app.route(\"/\")\ndef index(): pass"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_decorator_class" {
  let source = "@dataclass\nclass Point: pass"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_multiple_decorators" {
  let source = "@staticmethod\n@cache\ndef compute(): pass"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_async_decorator" {
  let source = "@app.get(\"/\")\nasync def handler(): pass"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 2.2  赋值目标扩展 (tuple/star unpack)
// ============================================================

///|
test "python_tuple_unpack_assign" {
  let source =
    #|a, b = [1, 2]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_star_unpack_assign" {
  let source =
    #|first, *rest = [1, 2, 3, 4]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_triple_unpack" {
  let source =
    #|a, b, c = [1, 2, 3]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 2.3  yield / await
// ============================================================

///|
test "python_yield_expression" {
  let source =
    #|yield 42
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_yield_from" {
  let source =
    #|yield from range(10)
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_yield_bare" {
  let source =
    #|yield
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_await_expression" {
  let source =
    #|result = await fetch(url)
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 2.4  海象运算符 (walrus operator)
// ============================================================

///|
test "python_walrus_operator" {
  let source =
    #|if (n := 10) > 5: pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_walrus_in_while" {
  let source =
    #|while (line := "hello") != "": pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 2.5  仅位置参数分隔符 / (positional-only)
// ============================================================

///|
test "python_positional_only_params" {
  let source =
    #|def f(a, b, /, c, d): pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

// ============================================================
// 3.  复杂集成测试 — 小功能实现
// ============================================================

///|
test "python_complex_fibonacci_memo" {
  // 带缓存的斐波那契 + 字典 + 条件 + 递归 + augmented assign
  let source =
    #|cache = {}
    #|def fib(n):
    #|    if n in cache:
    #|        return cache[n]
    #|    if n <= 1:
    #|        result = n
    #|    else:
    #|        result = fib(n - 1) + fib(n - 2)
    #|    cache[n] = result
    #|    return result
    #|total = 0
    #|for i in range(20):
    #|    total += fib(i)
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_linked_list_class" {
  // 链表类 + 装饰器 + 方法 + while + 比较 + is
  let source =
    #|class Node:
    #|    def __init__(self, val, nxt):
    #|        self.val = val
    #|        self.nxt = nxt
    #|
    #|@staticmethod
    #|def from_list(xs):
    #|    head = None
    #|    for x in reversed(xs):
    #|        head = Node(x, head)
    #|    return head
    #|
    #|def to_list(head):
    #|    result = []
    #|    cur = head
    #|    while cur is not None:
    #|        result = result + [cur.val]
    #|        cur = cur.nxt
    #|    return result
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_sort_and_filter" {
  // 综合：列表推导 + 条件表达式 + lambda + 切片 + 比较
  let source =
    #|data = [3, 1, 4, 1, 5, 9, 2, 6]
    #|evens = [x for x in data if x % 2 == 0]
    #|odds = [x for x in data if x % 2 != 0]
    #|pairs = [(x, y) for x in evens for y in odds if x < y]
    #|first_three = data[0:3]
    #|last_two = data[-2:]
    #|classify = lambda x: "big" if x > 5 else "small"
    #|labels = [classify(x) for x in data]
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_exception_handling" {
  // try/except/finally + raise + as + 多 except + 嵌套调用
  let source =
    #|def safe_divide(a, b):
    #|    try:
    #|        if b == 0:
    #|            raise ValueError("division by zero")
    #|        result = a / b
    #|    except ValueError as e:
    #|        result = -1
    #|    except Exception as e:
    #|        result = -2
    #|    finally:
    #|        done = True
    #|    return result
    #|
    #|def run_tests():
    #|    assert safe_divide(10, 2) == 5
    #|    assert safe_divide(10, 0) == -1
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_dict_manipulation" {
  // 字典推导 + 嵌套字典 + 解包 + del + in
  let source =
    #|raw = {'a': 1, 'b': 2, 'c': 3, 'd': 4}
    #|doubled = {k: v * 2 for k, v in raw.items() if v > 1}
    #|nested = {'outer': {'inner': [1, 2, 3]}}
    #|val = nested['outer']['inner'][0]
    #|del raw['d']
    #|exists = 'a' in raw
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_generator_pattern" {
  // yield + yield from + 装饰器 + 函数组合
  let source =
    #|def count_up(start, end):
    #|    n = start
    #|    while n < end:
    #|        yield n
    #|        n += 1
    #|
    #|def count_chain(ranges):
    #|    for s, e in ranges:
    #|        yield from count_up(s, e)
    #|
    #|@staticmethod
    #|def collect(gen):
    #|    result = []
    #|    for item in gen:
    #|        result = result + [item]
    #|    return result
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_async_web_handler" {
  // async def + 装饰器 + await + try/except + with + 字典
  let source =
    #|@app.get("/users")
    #|async def get_users(request):
    #|    try:
    #|        data = await fetch_db("SELECT * FROM users")
    #|        return {'status': 'ok', 'data': data}
    #|    except Exception as e:
    #|        return {'status': 'error', 'message': 'fail'}
    #|
    #|@app.post("/users")
    #|async def create_user(request):
    #|    body = await request.json()
    #|    name = body['name']
    #|    return {'id': 1, 'name': name}
  let node = parse_python_ok(source)
  let tree = python_tree(source)
  println("CST Tree:\n\{tree}")
  assert_true(!node.is_error)
}

///|
test "python_complex_matrix_ops" {
  // 嵌套列表推导 + 切片 + 多重赋值 + 复杂表达式 + 位运算
  let source =
    #|rows = 4
    #|cols = 4
    #|matrix = [[i * cols + j for j in range(cols)] for i in range(rows)]
    #|flat = [x for row in matrix for x in row]
    #|first_row = matrix[0][:]
    #|a, b, c = [1, 2, 3]
    #|flags = (a & 0xFF) | (b << 8) ^ (c >> 2)
    #|mask = ~flags & 0xFFFF
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_walrus_and_loop" {
  // 海象运算符 + while 循环 + break + 列表追加 + 条件
  let source =
    #|def read_chunks(stream, size):
    #|    chunks = []
    #|    while (chunk := stream.read(size)) != "":
    #|        if len(chunk) < size:
    #|            chunks = chunks + [chunk]
    #|            break
    #|        chunks = chunks + [chunk]
    #|    return chunks
    #|
    #|def find_first(predicate, items):
    #|    for i in range(len(items)):
    #|        if (val := items[i]) is not None:
    #|            if predicate(val):
    #|                return val
    #|    return None
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_class_hierarchy" {
  // 类继承 + 多装饰器 + @staticmethod + global + nonlocal
  let source =
    #|counter = 0
    #|
    #|class Shape:
    #|    def area(self):
    #|        return 0
    #|
    #|class Circle(Shape):
    #|    def __init__(self, r):
    #|        self.r = r
    #|    def area(self):
    #|        return 3.14159 * self.r ** 2
    #|
    #|@staticmethod
    #|def make_circle(r):
    #|    global counter
    #|    counter += 1
    #|    return Circle(r)
    #|
    #|def outer():
    #|    total = 0
    #|    def inner(x):
    #|        nonlocal total
    #|        total += x
    #|        return total
    #|    return inner
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_string_processing" {
  // 字符串操作 + 多种字面量 + f-string + 三引号 + 切片
  let source =
    #|name = "world"
    #|greeting = f"hello {name}!"
    #|raw = r"no\escape\here"
    #|multi = """line one
    #|line two
    #|line three"""
    #|upper = greeting[0:5]
    #|joined = ", ".join(["a", "b", "c"])
    #|template = b"bytes content"
    #|encoded = rb"raw bytes"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_power_and_unary" {
  // 幂运算 + 一元运算 + 复数 + 连续运算
  let source =
    #|a = 2 ** 10
    #|b = -a
    #|c = +b
    #|d = ~0xFF
    #|e = (-1) ** 2
    #|f = 2 ** 2 ** 3
    #|g = 3.14j
    #|h = 1e-5
    #|i = 0xFF + 0b1010 + 0o77
  let node = parse_python_ok(source)
  let tree = python_tree(source)
  println("CST Tree:\n\{tree}")
  assert_true(!node.is_error)
}

///|
test "python_complex_star_unpack_real" {
  // 星号解包 + for 元组解包 + 多目标赋值
  let source =
    #|def split_data(items):
    #|    first, *middle, last = items
    #|    head, *tail = [1, 2, 3, 4, 5]
    #|    return first, middle, last
    #|
    #|def process_records(records):
    #|    for name, age in records:
    #|        if age >= 18:
    #|            pass
    #|
    #|config = {'debug': True, 'verbose': False}
    #|keys = {k for k in config}
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_with_and_ellipsis" {
  // with 语句 + 省略号 + pass + type hint + 多 with
  let source =
    #|def read_file(path: str) -> str:
    #|    with open(path) as f:
    #|        return f.read()
    #|
    #|def stub_function(x: int, y: float) -> bool:
    #|    ...
    #|
    #|class Protocol:
    #|    def method(self):
    #|        ...
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_chained_comparison" {
  // 链式比较 + 复杂布尔 + not in + is not
  let source =
    #|def validate(x, lo, hi, blacklist):
    #|    if lo <= x <= hi:
    #|        if x not in blacklist:
    #|            if x is not None:
    #|                return True
    #|    result = (x > 0 and x < 100) or (x == -1 and not False)
    #|    return result
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_complex_full_program" {
  // 综合：import + 类 + 装饰器 + 推导 + 异常处理 + lambda + 各种表达式
  let source =
    #|from collections import defaultdict
    #|import math
    #|
    #|class Vector:
    #|    def __init__(self, x, y):
    #|        self.x = x
    #|        self.y = y
    #|    def length(self):
    #|        return math.sqrt(self.x ** 2 + self.y ** 2)
    #|    def __add__(self, other):
    #|        return Vector(self.x + other.x, self.y + other.y)
    #|
    #|@staticmethod
    #|def normalize(v):
    #|    l = v.length()
    #|    if l == 0:
    #|        raise ValueError("cannot normalize zero vector")
    #|    return Vector(v.x / l, v.y / l)
    #|
    #|vectors = [Vector(i, i * 2) for i in range(1, 6)]
    #|lengths = [v.length() for v in vectors]
    #|long_ones = [v for v in vectors if v.length() > 5.0]
    #|total = Vector(0, 0)
    #|for v in vectors:
    #|    total = total + v
    #|
    #|classify = lambda v: "long" if v.length() > 5 else "short"
    #|counts = defaultdict(int)
    #|for v in vectors:
    #|    counts[classify(v)] += 1
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_nested_if_elif_else" {
  let source =
    #|def classify(x):
    #|    if x > 0:
    #|        if x > 100:
    #|            return "big"
    #|        elif x > 10:
    #|            return "medium"
    #|        else:
    #|            return "small"
    #|    elif x == 0:
    #|        return "zero"
    #|    else:
    #|        return "negative"
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_nested_def" {
  let source =
    #|def outer(x):
    #|    def middle(y):
    #|        def inner(z):
    #|            return x + y + z
    #|        return inner(3)
    #|    return middle(2)
    #|result = outer(1)
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_nested_try_except" {
  let source =
    #|def process(data):
    #|    try:
    #|        try:
    #|            result = int(data)
    #|        except ValueError:
    #|            result = 0
    #|    except Exception as e:
    #|        result = -1
    #|    finally:
    #|        done = True
    #|    return result
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_deep_nesting_4_levels" {
  let source =
    #|def f():
    #|    if True:
    #|        for x in [1]:
    #|            while x > 0:
    #|                x = x - 1
    #|            pass
    #|        pass
    #|    pass
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_mixed_indent_widths" {
  // 不同函数使用不同的缩进宽度
  let source =
    #|def two_space():
    #|  x = 1
    #|  return x
    #|
    #|def four_space():
    #|    y = 2
    #|    return y
    #|
    #|def one_space():
    #| z = 3
    #| return z
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_class_with_nested_methods" {
  let source =
    #|class Calculator:
    #|    def __init__(self):
    #|        self.value = 0
    #|    def add(self, x):
    #|        self.value = self.value + x
    #|        return self
    #|    def reset(self):
    #|        self.value = 0
    #|        return self
    #|
    #|c = Calculator()
    #|c.add(5).add(3).reset()
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_nested_with_decorator_and_blank_lines" {
  let source =
    #|@staticmethod
    #|def outer():
    #|    x = 1
    #|
    #|    def inner():
    #|        return x
    #|
    #|    return inner()
  let node = parse_python_ok(source)
  assert_true(!node.is_error)
}

///|
test "python_snapshot / nested if suite" {
  inspect(
    @grammars.python_sexp("if True:\n    x = 1"),
    content=(
      #|(module (EOF) (statement (compound_statement (if_statement (expression (conditional_expression (or_expression (and_expression (not_expression (comparison_expression (bitwise_or_expression (bitwise_xor_expression (bitwise_and_expression (shift_expression (additive_expression (multiplicative_expression (power_expression (unary_expression (postfix_expression (primary_expression (literal))))))))))))))))) (suite (statement (simple_statement (assign_statement (target (identifier)) (expression (conditional_expression (or_expression (and_expression (not_expression (comparison_expression (bitwise_or_expression (bitwise_xor_expression (bitwise_and_expression (shift_expression (additive_expression (multiplicative_expression (power_expression (unary_expression (postfix_expression (primary_expression (literal (number_literal))))))))))))))))))))))))))
    ),
  )
}
