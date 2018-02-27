
#include <ctype.h>
#include <unistd.h>
#include <float.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#define LUA_MAXCAPTURES		32

typedef struct MatchState {
  int matchdepth;  /* control for recursive depth (to avoid C stack overflow) */
  const char *src_init;  /* init of source string */
  const char *src_end;  /* end ('\0') of source string */
  int src_len;
  const char *p_init;
  const char *p_end;  /* end ('\0') of pattern */
  int p_len;
  int level;  /* total number of captures (finished or unfinished) */
  struct {
    const char *init;
    int len;
    int start;
  } capture[LUA_MAXCAPTURES];
} MatchState;



#define lua_assert assert

typedef struct {
} lua_State;

#define luaL_error printf


/* macro to 'unsign' a character */
#define uchar(c)	((unsigned char)(c))


#define CAP_UNFINISHED	(-1)
#define CAP_POSITION	(-2)


/* recursive function */
int match (MatchState *ms, int si, int pi);


/* maximum recursion depth for 'match' */
#if !defined(MAXCCALLS)
#define MAXCCALLS	200
#endif


#define L_ESC		'%'
#define SPECIALS	"^$*+?.([%-"

int check_capture (MatchState *ms, int l);

int _check_capture (MatchState *ms, int l) {
  l -= '1';
  if (l < 0 || l >= ms->level || ms->capture[l].len == CAP_UNFINISHED)
    return luaL_error("invalid capture index %%%d", l + 1);
  return l;
}


int capture_to_close (MatchState *ms);

int _capture_to_close (MatchState *ms) {
  int level = ms->level;
  for (level--; level>=0; level--) {
    printf("B %d\n", level);
    if (ms->capture[level].len == CAP_UNFINISHED) return level;
  }
  return luaL_error("invalid pattern capture");
}


int classend (MatchState *ms, int pi) {
  printf("classend %d\n", pi);
  switch (ms->p_init[pi++]) {
    case L_ESC: {
      if (pi == ms->p_len)
        luaL_error("malformed pattern (ends with '%%')");
      return pi+1;
    }
    case '[': {
      if (ms->p_init[pi] == '^') pi++;
      do {  /* look for a ']' */
        if (pi == ms->p_len)
          luaL_error("malformed pattern (missing ']')");
        if (ms->p_init[pi++] == L_ESC && pi < ms->p_len)
          pi++;  /* skip escapes (e.g. '%]') */
      } while (ms->p_init[pi] != ']');
      return pi+1;
    }
    default: {
      return pi;
    }
  }
}


int match_class (int c, int cl);


int matchbracketclass (MatchState *ms, int c, int pi, int ec)
{
  int sig = 1;
  if (ms->p_init[pi+1] == '^') {
    sig = 0;
    pi++;  /* skip the '^' */
  }
  while (++pi < ec) {
    if (ms->p_init[pi] == L_ESC) {
      pi++;
      if (match_class(c, uchar(ms->p_init[pi])))
        return sig;
    }
    else if ((ms->p_init[pi+1] == '-') && (pi+2 < ec)) {
      pi+=2;
      if (uchar(ms->p_init[pi-2]) <= c && c <= uchar(ms->p_init[pi]))
        return sig;
    }
    else if (ms->p_init[pi] == c) return sig;
  }
  return !sig;
}


int singlematch (MatchState *ms, int si, int pi, int ep)
{
  if (si >= ms->src_len)
    return 0;
  else {
    int c = uchar(ms->src_init[si]);
    switch (ms->p_init[pi]) {
      case '.': return 1;  /* matches any char */
      case L_ESC: return match_class(c, uchar(ms->p_init[pi+1]));
      case '[': return matchbracketclass(ms, c, pi, ep-1);
      default:  return (uchar(ms->p_init[pi]) == c);
    }
  }
}


int matchbalance (MatchState *ms, int si, int pi)
{
  if (pi >= ms->p_len - 1)
    luaL_error("malformed pattern (missing arguments to '%%b')");
  if (ms->src_init[si] != ms->p_init[pi]) return -1;
  else {
    int b = ms->p_init[pi];
    int e = ms->p_init[pi+1];
    int cont = 1;
    while (++si < ms->src_len) {
      if (ms->src_init[si] == e) {
        if (--cont == 0) return si+1;
      }
      else if (ms->src_init[si] == b) cont++;
    }
  }
  return -1;  /* string ends out of balance */
}


int max_expand (MatchState *ms, int si, int pi, int ep)
{
  ptrdiff_t i = 0;  /* counts maximum expand for item */
  while (singlematch(ms, si + i, pi, ep))
    i++;
  /* keeps trying to match with the maximum repetitions */
  while (i>=0) {
    int res = match(ms, ms->src_init + si+i, ms->p_init + ep + 1);
    if (res != -1) return res;
    i--;  /* else didn't match; reduce 1 repetition to try again */
  }
  return -1;
}


int min_expand (MatchState *ms, int si, int pi, int ep)
{
  for (;;) {
    int = match(ms, si, ep+1);
    if (res != NULL)
      return res;
    else if (singlematch(ms, si, pi, ep))
      si++;  /* try with one more repetition */
    else return -1;
  }
}


int start_capture (MatchState *ms, int si, int pi, int what)
{
  int res;
  printf("  start '%s' '%s'\n", ms->src_init+si, ms->p_init+pi);
  int level = ms->level;
  if (level >= LUA_MAXCAPTURES) luaL_error("too many captures");
  ms->capture[level].init = ms->src_init+si;
  ms->capture[level].len = what;
  ms->capture[level].start = si;
  ms->level = level+1;
  if ((res=match(ms, si, pi)) == NULL)  /* match failed? */
    ms->level--;  /* undo capture */
  return res;
}


int end_capture (MatchState *ms, int si, int pi)
{
  printf("  end '%s' '%s'\n", ms->src_init+si, ms->p_init+pi);
  int l = capture_to_close(ms);
  int res;
  ms->capture[l].len = si;
  if ((res = match(ms, si, pi)) == NULL)  /* match failed? */
    ms->capture[l].len = CAP_UNFINISHED;  /* undo capture */
  return res;
}


int match_capture (MatchState *ms, int si, int l) {
  int len;
  l = check_capture(ms, l);
  len = ms->capture[l].len;
  if (si >= len &&
      memcmp(ms->capture[l].init, ms->src_init+si, len) == 0)
    return si+len;
  else return NULL;
}


int match (MatchState *ms, int si, int pi)
{
  assert(si >= 0);
  assert(pi >= 0);
  assert(si < ms->src_len);
  assert(pi < ms->p_len);

	printf("match '%s' '%s'\n", ms->src_init+si, ms->p_init+pi);
  if (ms->matchdepth-- == 0)
    luaL_error("pattern too complex");
  init: /* using goto's to optimize tail recursion */
  if (pi != ms->p_len) {  /* end of pattern? */
    switch (ms->p_init[pi]) {
      case '(': {  /* start capture */
        if (ms->p_init[pi+1] == ')')  /* position capture? */
          si = start_capture(ms, si, pi + 2, CAP_POSITION);
        else
          si = start_capture(ms, si, pi + 1, CAP_UNFINISHED);
        break;
      }
      case ')': {  /* end capture */
        si = end_capture(ms, si, pi + 1);
        break;
      }
      case '$': {
        if ((pi + 1) != ms->p_len)  /* is the '$' the last char in pattern? */
          goto dflt;  /* no; go to default */
        si = (si == ms->src_len) ? si : -1;  /* check end of string */
        break;
      }
      case L_ESC: {  /* escaped sequences not in the format class[*+?-]? */
        switch (ms->p_init[pi + 1]) {
          case 'b': {  /* balanced string? */
            si = matchbalance(ms, si, pi + 2);
            if (si != -1) {
              pi += 4; goto init;  /* return match(ms, s, p + 4); */
            }  /* else fail (s == NULL) */
            break;
          }
          case 'f': {  /* frontier? */
            int ep; char previous;
            pi += 2;
            if (ms->p_init[pi] != '[')
              luaL_error("missing '[' after '%%f' in pattern");
            ep = classend(ms, pi);  /* points to what is next */
            previous = (si == ms->src_len) ? '\0' : ms->src_init[si-1];
            if (!matchbracketclass(ms, uchar(previous), pi, ep - 1) &&
               matchbracketclass(ms, uchar(ms->src_init[si]), pi, ep - 1)) {
              pi = ep; goto init;  /* return match(ms, s, ep); */
            }
            si = -1;  /* match failed */
            break;
          }
          case '0': case '1': case '2': case '3':
          case '4': case '5': case '6': case '7':
          case '8': case '9': {  /* capture results (%0-%9)? */
            si = match_capture(ms, si, uchar(ms->p_init[pi+1]));
            if (si != -1) {
              pi += 2; goto init;  /* return match(ms, s, p + 2) */
            }
            break;
          }
          default: goto dflt;
        }
        break;
      }
      default: dflt: {  /* pattern class plus optional suffix */
        int ep = classend(ms, pi);  /* points to optional suffix */
        /* does not match at least once? */
        if (!singlematch(ms, si, pi, ep)) {
          if (ms->p_init[ep] == '*' || ms->p_init[ep] == '?' || ms->p_init[ep] == '-') {  /* accept empty? */
            pi = ep + 1; goto init;  /* return match(ms, s, ep + 1); */
          }
          else  /* '+' or no suffix */
            si = -1;  /* fail */
        }
        else {  /* matched once */
          switch (ms->p_init[ep]) {  /* handle optional suffix */
            case '?': {  /* optional */
              int res;
              if ((res = match(ms, si + 1, ep + 1)) != NULL)
                si = res;
              else {
                pi = ep + 1; goto init;  /* else return match(ms, s, ep + 1); */
              }
              break;
            }
            case '+':  /* 1 or more repetitions */
              si++;  /* 1 match already done */
              /* FALLTHROUGH */
            case '*':  /* 0 or more repetitions */
              si = max_expand(ms, si, pi, ep);
              break;
            case '-':  /* 0 or more repetitions (minimum) */
              si = min_expand(ms, si, pi, ep);
              break;
            default:  /* no suffix */
              si++; pi = ep; goto init;  /* return match(ms, s + 1, ep); */
          }
        }
        break;
      }
    }
  }
  ms->matchdepth++;
  return si;
}


const char *lmemfind (const char *s1, int l1,
                               const char *s2, int l2) {
  if (l2 == 0) return s1;  /* empty strings are everywhere */
  else if (l2 > l1) return NULL;  /* avoids a negative 'l1' */
  else {
    const char *init;  /* to search for a '*s2' inside 's1' */
    l2--;  /* 1st char will be checked by 'memchr' */
    l1 = l1-l2;  /* 's2' cannot be found after that */
    while (l1 > 0 && (init = (const char *)memchr(s1, *s2, l1)) != NULL) {
      init++;   /* 1st char is already checked */
      if (memcmp(init, s2+1, l2) == 0)
        return init-1;
      else {  /* correct 'l1' and 's1' to try again */
        l1 -= init-s1;
        s1 = init;
      }
    }
    return NULL;  /* not found */
  }
}


void push_onecapture (MatchState *ms, int i, const char *s,
                                                    const char *e) 
{
  if (i >= ms->level) {
    if (i == 0)  /* ms->level == 0, too */
      printf("push_onecapture '%s'\n", s);
      //lua_pushlstring(s, e - s);  /* add whole match */
    else
      luaL_error("invalid capture index %%%d", i + 1);
  }
  else {
    ptrdiff_t l = ms->capture[i].len;
    if (l == CAP_UNFINISHED) luaL_error("unfinished capture");
    if (l == CAP_POSITION)
      printf("pushpos %d\n", (ms->capture[i].init - ms->src_init) + 1);
      //lua_pushinteger((ms->capture[i].init - ms->src_init) + 1);
      //
    else
      printf("push_onecapture '%s'\n", ms->capture[i].init);
      //lua_pushlstring(ms->capture[i].init, l);
  }
}


int push_captures (MatchState *ms, const char *s, const char *e) {
  int i;
  int nlevels = (ms->level == 0 && s) ? 1 : ms->level;
  for (i = 0; i < nlevels; i++)
    push_onecapture(ms, i, s, e);
  return nlevels;  /* number of strings pushed */
}


/* check whether pattern has no special characters */
int nospecials (const char *p, int l) {
  int upto = 0;
  do {
    if (strpbrk(p + upto, SPECIALS))
      return 0;  /* pattern has a special character */
    upto += strlen(p + upto) + 1;  /* may have more after \0 */
  } while (upto <= l);
  return 1;  /* no special chars found */
}


int str_find_aux (int find, const char *s, const char *p, int init, int plain) 
{
  int ls = strlen(s);
  int lp = strlen(p);
  if (init < 1) init = 1;
  else if (init > (int)ls + 1) {  /* start after string's end? */
    printf("cannot find anything");
    return 1;
  }
  /* explicit request or no special characters? */
  if (find && (plain || nospecials(p, lp))) {
    /* do a plain search */
    const char *s2 = lmemfind(s + init - 1, ls - (int)init + 1, p, lp);
    if (s2) {
	    printf("push %d\n", (s2 - s) + 1);
	    printf("push %d\n", (s2 - s) + lp);
      return 2;
    }
  }
  else {
    MatchState ms;
    int pi = 0;
    const char *s1 = s + init - 1;
    int si = init-1;
    int anchor = (*p == '^');
    if (anchor) {
      pi ++;
      p++; lp--;  /* skip anchor character */
    }
    ms.matchdepth = MAXCCALLS;
    ms.src_init = s;
    ms.src_end = s + ls;
    ms.src_len = ls;
    ms.p_end = p + lp;
    ms.p_init = p;
    ms.p_len = lp;
    do {
      int res;
      ms.level = 0;
      lua_assert(ms.matchdepth == MAXCCALLS);
      if ((res=match(&ms, si, pi)) != NULL) {
        if (find) {
          printf("push %d\n", s1 + 1);  /* start */
          printf("push %d\n", res);   /* end */
          return push_captures(&ms, NULL, 0) + 2;
        }
        else
          return push_captures(&ms, s1, res);
      }
    } while (s1++ < ms.src_end && !anchor);
  }
  printf("not found\n");
  return 1;
}

/* 
 * vi: et sw=2 ts=2
 */
