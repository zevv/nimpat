
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
  const char *src;  /* init of source string */
  int src_len;
  const char *pat;
  int pat_len;
  int level;  /* total number of captures (finished or unfinished) */
  struct {
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
int capture_to_close (MatchState *ms);
int classend (MatchState *ms, int pi);
int match_class (int c, int cl);
int matchbracketclass (MatchState *ms, int c, int pi, int ec);
int singlematch (MatchState *ms, int si, int pi, int ep);
int matchbalance (MatchState *ms, int si, int pi);
int max_expand (MatchState *ms, int si, int pi, int ep);
int min_expand (MatchState *ms, int si, int pi, int ep);
int start_capture (MatchState *ms, int si, int pi, int what);
int end_capture (MatchState *ms, int si, int pi);
int match_capture (MatchState *ms, int si, int l);
const int match (MatchState *ms, int si, int pi);




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


void show(MatchState *ms)
{
  int i;
  for(i=0; i<ms->level; i++) {
    char *buf = ms->src + ms->capture[i].start;
    int len = ms->capture[i].len;
    printf("%d: (%d) ", i, len);
		if(len >= 0) {
			fwrite(buf, len, 1, stdout);
		}
    printf("\n");
  }
}


int str_find_aux (int find, const char *s, const char *p, int init, int plain) 
{
  int ls = strlen(s);
  int lp = strlen(p);
  if (init < 0) init = 0;
  else if (init > (int)ls + 1) {  /* start after string's end? */
    printf("cannot find anything");
    return 1;
  }
  /* explicit request or no special characters? */
  if (find && plain) {
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
    int si = init;
    int pi = 0;
    int anchor = (*p == '^');
    if (anchor) {
      pi++;
      p++; lp--;  /* skip anchor character */
    }
    ms.matchdepth = MAXCCALLS;
    ms.src = s;
    ms.src_len = ls;
    ms.pat = p;
    ms.pat_len = lp;
    do {
      int res;
      ms.level = 0;
      lua_assert(ms.matchdepth == MAXCCALLS);
      if ((res=match(&ms, si, pi)) != -1) {
        printf("done\n");
        show(&ms);
        return;
      }
    } while (si++ < ms.src_len && !anchor);
  }
  printf("not found\n");
  return 1;
}

/* 
 * vi: et sw=2 ts=2
 */
