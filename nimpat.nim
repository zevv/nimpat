
#
# This is basically a straight port of the Lua pattern matching code from Lua
# 5.3.4 lstrlib.c. Pointer arithmatic has been refactored to create safe Nim
# code, and some code was changed to avoid goto's used in the original 
#

import strutils

const 
  CAP_UNFINISHED = -1
  CAP_POSITION = -2
  L_ESC = '%'
  MAXCCALLS = 200

type

  Capture = object
    len: int
    start: int

  MatchState = object
    matchdepth: int
    src: string
    src_len: int
    pat: string
    pat_len: int
    level: int
    captures: seq[ref Capture]

proc match(ms: ref MatchState; si2: int; pi2: int): int

proc classend (ms: ref MatchState, pi2: int): int =
  var pi = pi2
  let c = ms.pat[pi]
  inc(pi)
  case c
    of L_ESC:
      if pi == ms.pat_len:
        raise newException(ValueError, "malformed pattern (ends with '%')");
      return pi+1
    of '[':
      if ms.pat[pi] == '^':
        inc(pi)
      while true:
        if pi == ms.pat_len:
          raise newException(ValueError, "malformed pattern (missing ']')")
        let c = ms.pat[pi]
        inc(pi)
        if c == L_ESC and pi < ms.pat_len:
          inc(pi)  # skip escapes (e.g. '%]')
        if ms.pat[pi] == ']':
          break
      return pi+1;
    else:
      return pi

proc match_class*(c: cchar, cl: cchar): bool =
  var res: bool
  case toLowerAscii(cl)
    of 'a': res = isAlphaAscii(c)
    #of 'c': res = isCntrl(c)
    of 'd': res = isDigit(c)
    #of 'g': res = isGraph(c)
    of 'l': res = isLowerAscii(c)
    #of 'p': res = isPunct(c)
    of 's': res = isSpaceAscii(c)
    of 'u': res = isUpperAscii(c)
    of 'w': res = isAlphaNumeric(c)
    of 'x': res = c in HexDigits
    of 'z': res = (c == '\0')
    else: return (cl == c)
  return if isLowerAscii(cl): res else: not res

proc check_capture(ms: ref MatchState, cl: char): int =
  let c = parseInt($cl) - 1
  if c < 0 or c >= ms.level or ms.captures[c].len == CAP_UNFINISHED:
    raise newException(ValueError, "invalid capture index $1" % intToStr(c + 1))
  return c

proc capture_to_close(ms: ref MatchState): int =
  var level = ms.level - 1
  while level >= 0:
    if ms.captures[level].len == CAP_UNFINISHED:
      return level
    dec(level)
  raise newException(ValueError, "invalid pattern capture")

proc matchbracketclass(ms: ref MatchState, c: char, pi2: int, ec: int): bool =
  var sig = true
  var pi = pi2
  if ms.pat[pi+1] == '^':
    sig = false;
    inc(pi) # skip the '^'
  inc(pi)
  while pi < ec:
    if ms.pat[pi] == L_ESC:
      inc(pi)
      if match_class(c, ms.pat[pi]):
        return sig
    elif (ms.pat[pi+1] == '-') and (pi+2 < ec):
      inc(pi, 2)
      if ms.pat[pi-2] <= c and c <= ms.pat[pi]:
        return sig
    elif ms.pat[pi] == c:
      return sig
    inc(pi)
  
  return not sig;

proc singlematch (ms: ref MatchState, si, pi, ep: int): bool =
  if si >= ms.src_len:
    return false
  else:
    let c = ms.src[si];
    case ms.pat[pi]
      of '.': return true
      of L_ESC: return match_class(c, ms.pat[pi+1])
      of '[': return matchbracketclass(ms, c, pi, ep-1)
      else: return ms.pat[pi] == c

proc matchbalance (ms: ref MatchState, si2, pi: int): int = 
  var si = si2
  if pi >= ms.pat_len - 1:
    raise newException(ValueError, "malformed pattern (missing arguments to '%%b')")
  if ms.src[si] != ms.pat[pi]:
    return -1;
  else:
    let b = ms.pat[pi];
    let e = ms.pat[pi+1];
    var cont = 1;
    inc(si)
    while si < ms.src_len:
      if ms.src[si] == e:
        dec(cont)
        if cont == 0:
          return si+1
      elif ms.src[si] == b:
        inc(cont)
      inc(si)
  return -1

proc max_expand (ms: ref MatchState, si, pi, ep: int): int = 
  var i = 0
  while singlematch(ms, si + i, pi, ep):
    inc(i)
  while i >= 0: # keeps trying to match with the maximum repetitions
    var res = match(ms, si+i, ep + 1)
    if res != -1:
      return res
    dec(i)  # else didn't match; reduce 1 repetition to try again
  return -1

proc min_expand (ms: ref MatchState, si2, pi, ep: int): int =
  var si = si2
  while true:
    let res = match(ms, si, ep+1)
    if res != -1:
      return res;
    elif singlematch(ms, si, pi, ep):
      inc(si) # try with one more repetition
    else:
      return -1

proc start_capture (ms: ref MatchState, si, pi, what: int): int =
  let level = ms.level
  var cap = new Capture;
  ms.captures.add(cap)
  ms.captures[level].len = what;
  ms.captures[level].start = si;
  ms.level = level+1
  let res = match(ms, si, pi)
  if res == -1: # match failed?
    dec(ms.level) # undo capture
  return res

proc end_capture (ms: ref MatchState, si, pi: int): int = 
  let n = capture_to_close(ms)
  var cap = ms.captures[n]
  cap.len = si - ms.captures[n].start
  let res = match(ms, si, pi)
  if res == -1:
    ms.captures[n].len = CAP_UNFINISHED
  return res

proc memcmp(s1: string, o1: int, s2: string, o2: int, len: csize): int =
  var i = 0
  while i < len:
    if s1[o1+i] < s2[o2+i]:
      return -1
    elif s1[o1+i] > s2[o2+i]:
      return 1
    inc(i)
  return 0

proc match_capture (ms: ref MatchState, si: int, c: int): int =
  let n = check_capture(ms, cast[cchar](c));
  let len = ms.captures[n].len;
  if ms.src_len-si >= len and
      memcmp(ms.src, ms.captures[n].start, ms.src, si, len) == 0:
    return si+len
  else:
    return -1

proc match(ms: ref MatchState; si2: int; pi2: int): int =
  var si: int = si2
  var pi: int = pi2
  assert si >= 0
  assert pi >= 0

  proc do_default(): bool =
    let ep = classend(ms, pi) # points to optional suffix
    # does not match at least once?
    if not singlematch(ms, si, pi, ep):
      if ms.pat[ep] == '*' or ms.pat[ep] == '?' or ms.pat[ep] == '-': #  accept empty?
        pi = ep + 1
        return true
      else: #  '+' or no suffix
        si = -1 #  fail
    else: # matched once
      case ms.pat[ep] # handle optional suffix
      of '?': # optional
        let res = match(ms, si + 1, ep + 1)
        if res != -1:
          si = res
        else:
          pi = ep + 1
          return true
      of '+': # 1 or more repetitions
        inc(si) # 1 match already done
        si = max_expand(ms, si, pi, ep)
      of '*': # 0 or more repetitions
        si = max_expand(ms, si, pi, ep)
      of '-': # 0 or more repetitions (minimum)
        si = min_expand(ms, si, pi, ep)
      else: # no suffix
        inc(si)
        pi = ep
        return true
    return false

  dec(ms.matchdepth)
  if ms.matchdepth == 0:
    raise newException(ValueError, "pattern too complex")

  while true:
    var again: bool

    if pi != ms.pat_len: # end of pattern?

      case ms.pat[pi]
      of '(': # start capture
        if ms.pat[pi + 1] == ')':
          si = start_capture(ms, si, pi + 2, CAP_POSITION)
        else:
          si = start_capture(ms, si, pi + 1, CAP_UNFINISHED)

      of ')': # end capture
        si = end_capture(ms, si, pi + 1)
      of '$':
        if (pi + 1) != ms.pat_len: # is the '$' the last char in pattern?
          again = do_default()
        else:
          si = if (si == ms.src_len): si else: -1 # check end of string
      of L_ESC: # escaped sequences not in the format class[*+?-]?
        case ms.pat[pi + 1]
        of 'b': # balanced string?
          si = matchbalance(ms, si, pi + 2)
          if si != -1:
            inc(pi, 4)
            again = true
        of 'f': # frontier?
          inc(pi, 2)
          if ms.pat[pi] != '[':
            raise newException(ValueError, "missing \'[\' after \'%%f\' in pattern")
          let ep = classend(ms, pi) # points to what is next
          let previous = if (si == ms.src_len): '\0' else: ms.src[si - 1]
          if not matchbracketclass(ms, previous, pi, ep - 1) and
              matchbracketclass(ms, ms.src[si], pi, ep - 1):
            pi = ep
            again = true
          si = -1
        of Digits: # capture results (%0-%9)?
          si = match_capture(ms, si, cast[int](ms.pat[pi + 1]))
          if si != -1:
            inc(pi, 2)
            again = true
        else:
          again = do_default()
      else:
        again = do_default()

    if not again: break

  inc(ms.matchdepth)
  return si

proc get_one_capture(ms: ref MatchState, i, si, ei: int): string =
  if i >= ms.level:
    if i == 0: # ms.level == 0, too
      return ms.src.substr(si, ei-1) # add whole match
    else:
      raise newException(ValueError, "invalid capture index %" & $i)
  else:
    let cap = ms.captures[i]
    if cap.len == CAP_UNFINISHED:
      raise newException(ValueError, "unfinished capture")
    elif cap.len == CAP_POSITION:
      return "POS"
    else:
      return ms.src.substr(cap.start, cap.start+cap.len-1)

proc get_captures(ms: ref MatchState, si: int, ei: int): seq[string] =
  let n = if (ms.level == 0 and si != -1): 1 else: ms.level
  var cs = newSeq[string]()
  var i = 0
  while i < n:
    let c = get_one_capture(ms, i, si, ei)
    cs.add(c)
    inc(i)
  return cs

proc match(src: string, pat: string): seq[string] =
    
  var ms: ref MatchState
  new ms
  var si = 0
  var pi = 0

  let anchor = (pat[0] == '^')
  if anchor: inc(pi)
  
  ms.matchdepth = MAXCCALLS;
  ms.src = src;
  ms.src_len = src.len();
  ms.pat = pat;
  ms.pat_len = pat.len();
  ms.captures = newSeq[ref Capture]()

  while true:
    ms.level = 0
    assert ms.matchdepth == MAXCCALLS
    let res = match(ms, si, pi)
    if res != -1:
      return get_captures(ms, si, res)
    if not (si < ms.src_len and not anchor):
      break
    inc(si)



proc unit_test() =

  proc test(src, pat: string, exp: seq[string]) = 
    let res = src.match(pat)
    var ok = true
    if res.len == exp.len:
      var i = 0
      while i < exp.len:
        if res[i] != exp[i]:
          ok = false
        inc(i)
    else:
      ok = false
    if not ok:
      echo "fail ('$1', '$2') != '$3' " % [src, pat, repr(res)]

  test("123456", "(%d%d)(%d%d)", @["12", "34"])
  test("123456", ".(%d%d)(%d%d)", @["23", "45"])
  test("123456", "(%d%d)(%d%d)$", @["34", "56"])
  test("abcd", "((..)(..))", @["abcd", "ab", "cd"])
  test("aaab", ".*b", @["aaab"])
  test("aaa", ".*a", @["aaa"])
  test("b", ".*b", @["b"])
  test("aaab", ".+b", @["aaab"])
  test("aaa", ".+a", @["aaa"])
  test("b", ".+b",  nil)
  test("aaab", ".?b", @["ab"])
  test("aaa", ".?a", @["aa"])
  test("b", ".?b", @["b"])
  test("oo", "(.)%1", @["o"])
  test("==========", "^([=]*)=$", @["========="])
  test("==========", "^([=]*)=%1$", nil)
  test("alo xyzK", "(%w+)K", @["xyz"])
  test("254 K", "(%d*)K", @[""])
  test("alo ", "(%w*)$", @[""])
  test("alo ", "(%w+)$", nil)
  test("aloALO", "%l*", @["alo"])
  test("aLo_ALO", "%a*", @["aLo"])
  test("aaab", "a*", @["aaa"])
  test("aaa", "^.*$", @["aaa"])
  test("aaa", "b*", @[""])
  test("aaa", "ab*a", @["aa"])
  test("aba", "ab*a", @["aba"])
  test("aaab", "a+", @["aaa"])
  test("aaa", "^.+$", @["aaa"])
  test("aaa", "b+", nil)
  test("aaa", "ab+a", nil)
  test("aba", "ab+a", @["aba"])
  test("a$a", ".$", @["a"])
  test("a$a", ".%$", @["a$"])
  test("a$a", ".$.", @["a$a"])
  test("a$a", "$$", nil)
  test("a$b", "a$", nil)
  test("a$a", "$", @[""])
  test("", "b*", @[""])
  test("aaa", "bb*", nil)
  test("aaab", "a-", @[""])
  test("aaa", "^.-$", @["aaa"])
  test("aabaaabaaabaaaba", "b.*b", @["baaabaaabaaab"])
  test("aabaaabaaabaaaba", "b.-b", @["baaab"])
  test("alo xo", ".o$", @["xo"])
  test(" \n isto é assim", "%S%S*", @["isto"])
  test(" \n isto é assim", "%S*$", @["assim"])
  test(" \n isto é assim", "[a-z]*$", @["assim"])
  test("um caracter ? extra", "[^%sa-z]", @["?"])
  test("", "a?", @[""])
  test("á", "á?", @["á"])
  test("ábl", "á?b?l?", @["ábl"])
  test("aa", "^aa?a?a", @["aa"])
  test("0alo alo", "%x*", @["0a"])
  echo "Done"


unit_test()

# vi: ft=nim et ts=2 sw=2

