# Copyright (c) 2019 Jacek Sieka
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

type
  ResultError*[E] = object of ValueError
    ## Error raised when using `tryValue` value of result when error is set
    ## See also Exception bridge mode
    error*: E

  ResultDefect* = object of Defect
    ## Defect raised when accessing value when error is set and vice versa
    ## See also Exception bridge mode

  Result*[T, E] = object
    # ResultPrivate* works around (fixed in 1.6.14+):
    # * https://github.com/nim-lang/Nim/issues/3770
    # * https://github.com/nim-lang/Nim/issues/20900
    #
    # Do not use these fields directly in your code, they're not meant to be
    # public!
    when T is void:
      when E is void:
        oResultPrivate*: bool
      else:
        case oResultPrivate*: bool
        of false:
          eResultPrivate*: E
        of true:
          discard
    else:
      when E is void:
        case oResultPrivate*: bool
        of false:
          discard
        of true:
          vResultPrivate*: T
      else:
        case oResultPrivate*: bool
        of false:
          eResultPrivate*: E
        of true:
          vResultPrivate*: T

  Opt*[T] = Result[T, void]

const
  resultsGenericsOpenSym* {.booldefine.} = true
    ## Enable the experimental `genericsOpenSym` feature or a workaround for the
    ## template injection problem in the issue linked below where scoped symbol
    ## resolution works differently for expanded bodies in templates depending on
    ## whether we're in a generic context or not.
    ##
    ## The issue leads to surprising errors where symbols from outer scopes get
    ## bound instead of the symbol created in the template scope which should be
    ## seen as a better candidate, breaking access to `error` in `valueOr` and
    ## friends.
    ##
    ## In Nim versions that do not support `genericsOpenSym`, a macro is used
    ## instead to reassign symbol matches which may or may not work depending on
    ## the complexity of the code.
    ##
    ## Nim 2.0.8 was released with an incomplete fix but already declares
    ## `nimHasGenericsOpenSym`.
    # TODO https://github.com/nim-lang/Nim/issues/22605
    # TODO https://github.com/arnetheduck/nim-results/issues/34
    # TODO https://github.com/nim-lang/Nim/issues/23386
    # TODO https://github.com/nim-lang/Nim/issues/23385
    #
    # Related PR:s (there's more probably, but this gives an overview)
    # https://github.com/nim-lang/Nim/pull/23102
    # https://github.com/nim-lang/Nim/pull/23572
    # https://github.com/nim-lang/Nim/pull/23873
    # https://github.com/nim-lang/Nim/pull/23892
    # https://github.com/nim-lang/Nim/pull/23939

  resultsGenericsOpenSymWorkaround* {.booldefine.} =
    resultsGenericsOpenSym and not defined(nimHasGenericsOpenSym2)
    ## Prefer macro workaround to solve genericsOpenSym issue
    # TODO https://github.com/nim-lang/Nim/pull/23892#discussion_r1713434311

  resultsGenericsOpenSymWorkaroundHint* {.booldefine.} = true

template maybeLent(T: untyped): untyped =
  lent T

func raiseResultOk[T, E](self: Result[T, E]) {.noreturn, noinline.} =
  # noinline because raising should take as little space as possible at call
  # site
  when T is void:
    raise (ref ResultError[void])(msg: "Trying to access error with value")
  else:
    raise (ref ResultError[T])(
      msg: "Trying to access error with value", error: self.vResultPrivate
    )

func raiseResultError[T, E](self: Result[T, E]) {.noreturn, noinline.} =
  # noinline because raising should take as little space as possible at call
  # site
  mixin toException

  when E is ref Exception:
    if self.eResultPrivate.isNil: # for example Result.default()!
      raise (ref ResultError[void])(msg: "Trying to access value with err (nil)")
    raise self.eResultPrivate
  elif E is void:
    raise (ref ResultError[void])(msg: "Trying to access value with err")
  elif compiles(toException(self.eResultPrivate)):
    raise toException(self.eResultPrivate)
  elif compiles($self.eResultPrivate):
    raise (ref ResultError[E])(error: self.eResultPrivate, msg: $self.eResultPrivate)
  else:
    raise (ref ResultError[E])(
      msg: "Trying to access value with err", error: self.eResultPrivate
    )

func raiseResultDefect(m: string, v: auto) {.noreturn, noinline.} =
  mixin `$`
  when compiles($v):
    raise (ref ResultDefect)(msg: m & ": " & $v)
  else:
    raise (ref ResultDefect)(msg: m)

func raiseResultDefect(m: string) {.noreturn, noinline.} =
  raise (ref ResultDefect)(msg: m)

template withAssertOk(self: Result, body: untyped): untyped =
  # Careful - `self` evaluated multiple times, which is fine in all current uses
  case self.oResultPrivate
  of false:
    when self.E isnot void:
      raiseResultDefect("Trying to access value with err Result", self.eResultPrivate)
    else:
      raiseResultDefect("Trying to access value with err Result")
  of true:
    body

template ok*[T: not void, E](R: type Result[T, E], x: untyped): R =
  ## Initialize a result with a success and value
  ## Example: `Result[int, string].ok(42)`
  R(oResultPrivate: true, vResultPrivate: x)

template ok*[E](R: type Result[void, E]): R =
  ## Initialize a result with a success and value
  ## Example: `Result[void, string].ok()`
  R(oResultPrivate: true)

template ok*[T: not void, E](self: var Result[T, E], x: untyped) =
  ## Set the result to success and update value
  ## Example: `result.ok(42)`
  self = ok(type self, x)

template ok*[E](self: var Result[void, E]) =
  ## Set the result to success and update value
  ## Example: `result.ok()`
  self = (type self).ok()

template err*[T; E: not void](R: type Result[T, E], x: untyped): R =
  ## Initialize the result to an error
  ## Example: `Result[int, string].err("uh-oh")`
  R(oResultPrivate: false, eResultPrivate: x)

template err*[T](R: type Result[T, cstring], x: string): R =
  ## Initialize the result to an error
  ## Example: `Result[int, string].err("uh-oh")`
  const s = x # avoid dangling cstring pointers
  R(oResultPrivate: false, eResultPrivate: cstring(s))

template err*[T](R: type Result[T, void]): R =
  ## Initialize the result to an error
  ## Example: `Result[int, void].err()`
  R(oResultPrivate: false)

template err*[T; E: not void](self: var Result[T, E], x: untyped) =
  ## Set the result as an error
  ## Example: `result.err("uh-oh")`
  self = err(type self, x)

template err*[T](self: var Result[T, cstring], x: string) =
  const s = x # Make sure we don't return a dangling pointer
  self = err(type self, cstring(s))

template err*[T](self: var Result[T, void]) =
  ## Set the result as an error
  ## Example: `result.err()`
  self = err(type self)

template ok*(v: auto): auto =
  ok(typeof(result), v)

template ok*(): auto =
  ok(typeof(result))

template err*(v: auto): auto =
  err(typeof(result), v)

template err*(): auto =
  err(typeof(result))

template isOk*(self: Result): bool =
  self.oResultPrivate

template isErr*(self: Result): bool =
  not self.oResultPrivate

when not defined(nimHasEffectsOfs):
  template effectsOf(f: untyped) {.pragma, used.}

func map*[T0: not void, E; T1: not void](
    self: Result[T0, E], f: proc(x: T0): T1
): Result[T1, E] {.inline, effectsOf: f.} =
  ## Transform value using f, or return error
  ##
  ## ```
  ## let r = Result[int, cstring).ok(42)
  ## assert r.map(proc (v: int): int = $v).value() == "42"
  ## ```
  case self.oResultPrivate
  of true:
    when T1 is void:
      f(self.vResultPrivate)
      result.ok()
    else:
      result.ok(f(self.vResultPrivate))
  of false:
    when E is void:
      result.err()
    else:
      result.err(self.eResultPrivate)

func map*[T: not void, E](
    self: Result[T, E], f: proc(x: T)
): Result[void, E] {.inline, effectsOf: f.} =
  ## Transform value using f, or return error
  ##
  ## ```
  ## let r = Result[int, cstring).ok(42)
  ## assert r.map(proc (v: int): int = $v).value() == "42"
  ## ```
  case self.oResultPrivate
  of true:
    f(self.vResultPrivate)
    result.ok()
  of false:
    when E is void:
      result.err()
    else:
      result.err(self.eResultPrivate)

func map*[E; T1: not void](
    self: Result[void, E], f: proc(): T1
): Result[T1, E] {.inline, effectsOf: f.} =
  ## Transform value using f, or return error
  case self.oResultPrivate
  of true:
    result.ok(f())
  of false:
    when E is void:
      result.err()
    else:
      result.err(self.eResultPrivate)

func map*[E](
    self: Result[void, E], f: proc()
): Result[void, E] {.inline, effectsOf: f.} =
  ## Call f if `self` is ok
  case self.oResultPrivate
  of true:
    f()
    result.ok()
  of false:
    when E is void:
      result.err()
    else:
      result.err(self.eResultPrivate)

func flatMap*[T0: not void, E, T1](
    self: Result[T0, E], f: proc(x: T0): Result[T1, E]
): Result[T1, E] {.inline, effectsOf: f.} =
  case self.oResultPrivate
  of true:
    f(self.vResultPrivate)
  of false:
    when E is void:
      Result[T1, void].err()
    else:
      Result[T1, E].err(self.eResultPrivate)

func flatMap*[E, T1](
    self: Result[void, E], f: proc(): Result[T1, E]
): Result[T1, E] {.inline, effectsOf: f.} =
  case self.oResultPrivate
  of true:
    f()
  of false:
    when E is void:
      Result[T1, void].err()
    else:
      Result[T1, E].err(self.eResultPrivate)

func mapErr*[T; E0: not void, E1: not void](
    self: Result[T, E0], f: proc(x: E0): E1
): Result[T, E1] {.inline, effectsOf: f.} =
  ## Transform error using f, or leave untouched
  case self.oResultPrivate
  of true:
    when T is void:
      result.ok()
    else:
      result.ok(self.vResultPrivate)
  of false:
    result.err(f(self.eResultPrivate))

func mapErr*[T; E1: not void](
    self: Result[T, void], f: proc(): E1
): Result[T, E1] {.inline, effectsOf: f.} =
  ## Transform error using f, or return value
  case self.oResultPrivate
  of true:
    when T is void:
      result.ok()
    else:
      result.ok(self.vResultPrivate)
  of false:
    result.err(f())

func mapErr*[T; E0: not void](
    self: Result[T, E0], f: proc(x: E0)
): Result[T, void] {.inline, effectsOf: f.} =
  ## Transform error using f, or return value
  case self.oResultPrivate
  of true:
    when T is void:
      result.ok()
    else:
      result.ok(self.vResultPrivate)
  of false:
    f(self.eResultPrivate)
    result.err()

func mapErr*[T](
    self: Result[T, void], f: proc()
): Result[T, void] {.inline, effectsOf: f.} =
  ## Transform error using f, or return value
  case self.oResultPrivate
  of true:
    when T is void:
      result.ok()
    else:
      result.ok(self.vResultPrivate)
  of false:
    f()
    result.err()

func mapConvert*[T0: not void, E](
    self: Result[T0, E], T1: type
): Result[T1, E] {.inline.} =
  ## Convert result value to A using an conversion
  # Would be nice if it was automatic...
  case self.oResultPrivate
  of true:
    when T1 is void:
      result.ok()
    else:
      result.ok(T1(self.vResultPrivate))
  of false:
    when E is void:
      result.err()
    else:
      result.err(self.eResultPrivate)

func mapCast*[T0: not void, E](
    self: Result[T0, E], T1: type
): Result[T1, E] {.inline.} =
  ## Convert result value to A using a cast
  ## Would be nice with nicer syntax...
  case self.oResultPrivate
  of true:
    when T1 is void:
      result.ok()
    else:
      result.ok(cast[T1](self.vResultPrivate))
  of false:
    when E is void:
      result.err()
    else:
      result.err(self.eResultPrivate)

func mapConvertErr*[T, E0](self: Result[T, E0], E1: type): Result[T, E1] {.inline.} =
  ## Convert result error to E1 using an conversion
  # Would be nice if it was automatic...
  when E0 is E1:
    result = self
  else:
    if self.oResultPrivate:
      when T is void:
        result.ok()
      else:
        result.ok(self.vResultPrivate)
    else:
      when E1 is void:
        result.err()
      else:
        result.err(E1(self.eResultPrivate))

func mapCastErr*[T, E0](self: Result[T, E0], E1: type): Result[T, E1] {.inline.} =
  ## Convert result value to A using a cast
  ## Would be nice with nicer syntax...
  if self.oResultPrivate:
    when T is void:
      result.ok()
    else:
      result.ok(self.vResultPrivate)
  else:
    result.err(cast[E1](self.eResultPrivate))

template `and`*[T0, E, T1](self: Result[T0, E], other: Result[T1, E]): Result[T1, E] =
  ## Evaluate `other` iff self.isOk, else return error
  ## fail-fast - will not evaluate other if a is an error
  let s = (self) # TODO avoid copy
  case s.oResultPrivate
  of true:
    other
  of false:
    when type(self) is type(other):
      s
    else:
      type R = type(other)
      when E is void:
        err(R)
      else:
        err(R, s.eResultPrivate)

template `or`*[T, E0, E1](self: Result[T, E0], other: Result[T, E1]): Result[T, E1] =
  ## Evaluate `other` iff `not self.isOk`, else return `self`
  ## fail-fast - will not evaluate `other` if `self` is ok
  ##
  ## ```
  ## func f(): Result[int, SomeEnum] =
  ##   f2() or err(SomeEnum.V) # Collapse errors from other module / function
  ## ```
  let s = (self) # TODO avoid copy
  case s.oResultPrivate
  of true:
    when type(self) is type(other):
      s
    else:
      type R = type(other)
      when T is void:
        ok(R)
      else:
        ok(R, s.vResultPrivate)
  of false:
    other

template orErr*[T, E0, E1](self: Result[T, E0], error: E1): Result[T, E1] =
  ## Evaluate `other` iff `not self.isOk`, else return `self`
  ## fail-fast - will not evaluate `error` if `self` is ok
  ##
  ## ```
  ## func f(): Result[int, SomeEnum] =
  ##   f2().orErr(SomeEnum.V) # Collapse errors from other module / function
  ## ```
  ##
  ## ** Experimental, may be removed **
  let s = (self) # TODO avoid copy
  type R = Result[T, E1]
  case s.oResultPrivate
  of true:
    when type(self) is R:
      s
    else:
      when T is void:
        ok(R)
      else:
        ok(R, s.vResultPrivate)
  of false:
    err(R, error)

template catch*(body: typed): Result[type(body), ref CatchableError] =
  ## Catch exceptions for body and store them in the Result
  ##
  ## ```
  ## let r = catch: someFuncThatMayRaise()
  ## ```
  type R = Result[type(body), ref CatchableError]

  try:
    when type(body) is void:
      body
      R.ok()
    else:
      R.ok(body)
  except CatchableError as eResultPrivate:
    R.err(eResultPrivate)

template capture*[E: Exception](T: type, someExceptionExpr: ref E): Result[T, ref E] =
  ## Evaluate someExceptionExpr and put the exception into a result, making sure
  ## to capture a call stack at the capture site:
  ##
  ## ```
  ## let eResultPrivate: Result[void, ValueError] = void.capture((ref ValueError)(msg: "test"))
  ## echo eResultPrivate.error().getStackTrace()
  ## ```
  type R = Result[T, ref E]

  var ret: R
  try:
    # TODO is this needed? I think so, in order to grab a call stack, but
    #      haven't actually tested...
    if true:
      # I'm sure there's a nicer way - this just works :)
      raise someExceptionExpr
  except E as caught:
    ret = R.err(caught)
  ret

func `==`*[T0: not void, E0: not void, T1: not void, E1: not void](
    lhs: Result[T0, E0], rhs: Result[T1, E1]
): bool {.inline.} =
  if lhs.oResultPrivate != rhs.oResultPrivate:
    false
  else:
    case lhs.oResultPrivate # and rhs.oResultPrivate implied
    of true:
      lhs.vResultPrivate == rhs.vResultPrivate
    of false:
      lhs.eResultPrivate == rhs.eResultPrivate

func `==`*[E0, E1](lhs: Result[void, E0], rhs: Result[void, E1]): bool {.inline.} =
  if lhs.oResultPrivate != rhs.oResultPrivate:
    false
  else:
    case lhs.oResultPrivate # and rhs.oResultPrivate implied
    of true:
      true
    of false:
      lhs.eResultPrivate == rhs.eResultPrivate

func `==`*[T0, T1](lhs: Result[T0, void], rhs: Result[T1, void]): bool {.inline.} =
  if lhs.oResultPrivate != rhs.oResultPrivate:
    false
  else:
    case lhs.oResultPrivate # and rhs.oResultPrivate implied
    of true:
      lhs.vResultPrivate == rhs.vResultPrivate
    of false:
      true

func value*[E](self: Result[void, E]) {.inline.} =
  ## Fetch value of result if set, or raise Defect
  ## Exception bridge mode: raise given Exception instead
  ## See also: Option.get
  withAssertOk(self):
    discard

func value*[T: not void, E](self: Result[T, E]): maybeLent T {.inline.} =
  ## Fetch value of result if set, or raise Defect
  ## Exception bridge mode: raise given Exception instead
  ## See also: Option.get
  withAssertOk(self):
    when T isnot void:
      # TODO: remove result usage.
      # A workaround for nim VM bug:
      # https://github.com/nim-lang/Nim/issues/22216
      result = self.vResultPrivate

func value*[T: not void, E](self: var Result[T, E]): var T {.inline.} =
  ## Fetch value of result if set, or raise Defect
  ## Exception bridge mode: raise given Exception instead
  ## See also: Option.get

  (
    block:
      withAssertOk(self):
        addr self.vResultPrivate
  )[]

template `[]`*[T: not void, E](self: Result[T, E]): T =
  ## Fetch value of result if set, or raise Defect
  ## Exception bridge mode: raise given Exception instead
  self.value()

template `[]`*[E](self: Result[void, E]) =
  ## Fetch value of result if set, or raise Defect
  ## Exception bridge mode: raise given Exception instead
  self.value()

template unsafeValue*[T: not void, E](self: Result[T, E]): T =
  ## Fetch value of result if set, undefined behavior if unset
  ## See also: `unsafeError`
  self.vResultPrivate

template unsafeValue*[E](self: Result[void, E]) =
  ## Fetch value of result if set, undefined behavior if unset
  ## See also: `unsafeError`
  assert self.oResultPrivate # Emulate field access defect in debug builds

func tryValue*[E](self: Result[void, E]) {.inline.} =
  ## Fetch value of result if set, or raise
  ## When E is an Exception, raise that exception - otherwise, raise a ResultError[E]
  mixin raiseResultError
  case self.oResultPrivate
  of false:
    self.raiseResultError()
  of true:
    discard

func tryValue*[T: not void, E](self: Result[T, E]): maybeLent T {.inline.} =
  ## Fetch value of result if set, or raise
  ## When E is an Exception, raise that exception - otherwise, raise a ResultError[E]
  mixin raiseResultError
  case self.oResultPrivate
  of false:
    self.raiseResultError()
  of true:
    # TODO https://github.com/nim-lang/Nim/issues/22216
    result = self.vResultPrivate

func expect*[E](self: Result[void, E], m: string) =
  ## Return value of Result, or raise a `Defect` with the given message - use
  ## this helper to extract the value when an error is not expected, for example
  ## because the program logic dictates that the operation should never fail
  ##
  ## ```nim
  ## let r = Result[int, int].ok(42)
  ## # Put here a helpful comment why you think this won't fail
  ## echo r.expect("r was just set to ok(42)")
  ## ```
  case self.oResultPrivate
  of false:
    when E isnot void:
      raiseResultDefect(m, self.eResultPrivate)
    else:
      raiseResultDefect(m)
  of true:
    discard

func expect*[T: not void, E](self: Result[T, E], m: string): maybeLent T =
  ## Return value of Result, or raise a `Defect` with the given message - use
  ## this helper to extract the value when an error is not expected, for example
  ## because the program logic dictates that the operation should never fail
  ##
  ## ```nim
  ## let r = Result[int, int].ok(42)
  ## # Put here a helpful comment why you think this won't fail
  ## echo r.expect("r was just set to ok(42)")
  ## ```
  case self.oResultPrivate
  of false:
    when E isnot void:
      raiseResultDefect(m, self.eResultPrivate)
    else:
      raiseResultDefect(m)
  of true:
    # TODO https://github.com/nim-lang/Nim/issues/22216
    result = self.vResultPrivate

func expect*[T: not void, E](self: var Result[T, E], m: string): var T =
  (
    case self.oResultPrivate
    of false:
      when E isnot void:
        raiseResultDefect(m, self.eResultPrivate)
      else:
        raiseResultDefect(m)
    of true:
      addr self.vResultPrivate
  )[]

func `$`*[T, E](self: Result[T, E]): string =
  ## Returns string representation of `self`
  case self.oResultPrivate
  of true:
    when T is void:
      "ok()"
    else:
      "ok(" & $self.vResultPrivate & ")"
  of false:
    when E is void:
      "none()"
    else:
      "err(" & $self.eResultPrivate & ")"

func error*[T](self: Result[T, void]) =
  ## Fetch error of result if set, or raise Defect
  case self.oResultPrivate
  of true:
    when T isnot void:
      raiseResultDefect("Trying to access error when value is set", self.vResultPrivate)
    else:
      raiseResultDefect("Trying to access error when value is set")
  of false:
    discard

func error*[T; E: not void](self: Result[T, E]): maybeLent E =
  ## Fetch error of result if set, or raise Defect
  case self.oResultPrivate
  of true:
    when T isnot void:
      raiseResultDefect("Trying to access error when value is set", self.vResultPrivate)
    else:
      raiseResultDefect("Trying to access error when value is set")
  of false:
    # TODO https://github.com/nim-lang/Nim/issues/22216
    result = self.eResultPrivate

func tryError*[T](self: Result[T, void]) {.inline.} =
  ## Fetch error of result if set, or raise
  ## Raises a ResultError[T]
  mixin raiseResultOk
  case self.oResultPrivate
  of true:
    self.raiseResultOk()
  of false:
    discard

func tryError*[T; E: not void](self: Result[T, E]): maybeLent E {.inline.} =
  ## Fetch error of result if set, or raise
  ## Raises a ResultError[T]
  mixin raiseResultOk
  case self.oResultPrivate
  of true:
    self.raiseResultOk()
  of false:
    # TODO https://github.com/nim-lang/Nim/issues/22216
    result = self.eResultPrivate

template unsafeError*[T; E: not void](self: Result[T, E]): E =
  ## Fetch error of result if set, undefined behavior if unset
  ## See also: `unsafeValue`
  self.eResultPrivate

template unsafeError*[T](self: Result[T, void]) =
  ## Fetch error of result if set, undefined behavior if unset
  ## See also: `unsafeValue`
  assert not self.oResultPrivate # Emulate field access defect in debug builds

func optValue*[T, E](self: Result[T, E]): Opt[T] =
  ## Return the value of a Result as an Opt, or none if Result is an error
  case self.oResultPrivate
  of true:
    when T is void:
      Opt[void].ok()
    else:
      Opt.some(self.vResultPrivate)
  of false:
    Opt.none(T)

func optError*[T, E](self: Result[T, E]): Opt[E] =
  ## Return the error of a Result as an Opt, or none if Result is a value
  case self.oResultPrivate
  of true:
    Opt.none(E)
  of false:
    Opt.some(self.eResultPrivate)

# Alternative spellings for `value`, for `options` compatibility
template get*[T: not void, E](self: Result[T, E]): T =
  self.value()

template get*[E](self: Result[void, E]) =
  self.value()

template tryGet*[T: not void, E](self: Result[T, E]): T =
  self.tryValue()

template tryGet*[E](self: Result[void, E]) =
  self.tryValue()

template unsafeGet*[T: not void, E](self: Result[T, E]): T =
  self.unsafeValue()

template unsafeGet*[E](self: Result[void, E]) =
  self.unsafeValue()

# `var` overloads should not be needed but result in invalid codegen (!):
# https://github.com/nim-lang/Nim/issues/22049 (fixed in 1.6.16+)
func get*[T: not void, E](self: var Result[T, E]): var T =
  self.value()

func get*[T, E](self: Result[T, E], otherwise: T): T {.inline.} =
  ## Fetch value of result if set, or return the value `otherwise`
  ## See `valueOr` for a template version that avoids evaluating `otherwise`
  ## unless necessary
  case self.oResultPrivate
  of true: self.vResultPrivate
  of false: otherwise

# TODO https://github.com/nim-lang/Nim/pull/23892#discussion_r1713434311
const pushGenericsOpenSym = defined(nimHasGenericsOpenSym2) and resultsGenericsOpenSym

template isOkOr*[T, E](self: Result[T, E], body: untyped) =
  ## Evaluate `body` iff result has been assigned an error
  ## `body` is evaluated lazily.
  ##
  ## Example:
  ## ```
  ## let
  ##   v = Result[int, string].err("hello")
  ##   x = v.isOkOr: echo "not ok"
  ##   # experimental: direct error access using an unqualified `error` symbol
  ##   z = v.isOkOr: echo error
  ## ```
  ##
  ## `error` access:
  ##
  ## TODO experimental, might change in the future
  ##
  ## The template contains a shortcut for accessing the error of the result,
  ## it can only be used outside of generic code,
  ## see https://github.com/status-im/nim-stew/issues/161#issuecomment-1397121386

  let s = (self) # TODO avoid copy
  case s.oResultPrivate
  of false:
    when E isnot void:
      when pushGenericsOpenSym:
        {.push experimental: "genericsOpenSym".}
      template error(): E {.used.} =
        s.eResultPrivate

    body
  of true:
    discard

template isErrOr*[T, E](self: Result[T, E], body: untyped) =
  ## Evaluate `body` iff result has been assigned a value
  ## `body` is evaluated lazily.
  ##
  ## Example:
  ## ```
  ## let
  ##   v = Result[int, string].ok(42)
  ##   x = v.isErrOr: echo "not err"
  ##   # experimental: direct value access using an unqualified `value` symbol
  ##   z = v.isErrOr: echo value
  ## ```
  ##
  ## `value` access:
  ##
  ## TODO experimental, might change in the future
  ##
  ## The template contains a shortcut for accessing the value of the result,
  ## it can only be used outside of generic code,
  ## see https://github.com/status-im/nim-stew/issues/161#issuecomment-1397121386

  let s = (self) # TODO avoid copy
  case s.oResultPrivate
  of true:
    when T isnot void:
      when pushGenericsOpenSym:
        {.push experimental: "genericsOpenSym".}
      template value(): T {.used.} =
        s.vResultPrivate

    body
  of false:
    discard

template errorOr*[T; E: not void](self: Result[T, E], def: untyped): E =
  ## Fetch error of result if not set, or evaluate `def`
  ## `def` is evaluated lazily, and must be an expression of `T` or exit
  ## the scope (for example using `return` / `raise`)
  ##
  ## See `isErrOr` for a version that works with `Result[T, void]`.
  let s = (self) # TODO avoid copy
  case s.oResultPrivate
  of false:
    s.eResultPrivate
  of true:
    when T isnot void:
      when pushGenericsOpenSym:
        {.push experimental: "genericsOpenSym".}
      template value(): T {.used.} =
        s.vResultPrivate

    def

# Options compatibility

template some*[T](O: type Opt, v: T): Opt[T] =
  ## Create an `Opt` set to a value
  ##
  ## ```
  ## let oResultPrivate = Opt.some(42)
  ## assert oResultPrivate.isSome and oResultPrivate.value() == 42
  ## ```
  Opt[T].ok(v)

template none*(O: type Opt, T: type): Opt[T] =
  ## Create an `Opt` set to none
  ##
  ## ```
  ## let oResultPrivate = Opt.none(int)
  ## assert oResultPrivate.isNone
  ## ```
  Opt[T].err()

template isSome*(oResultPrivate: Opt): bool =
  ## Alias for `isOk`
  isOk oResultPrivate

template isNone*(oResultPrivate: Opt): bool =
  ## Alias of `isErr`
  isErr oResultPrivate
