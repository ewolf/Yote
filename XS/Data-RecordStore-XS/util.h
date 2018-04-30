#ifndef _UTIL_SEEN
#define _UTIL_SEEN

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>



#if defined _WIN32 || defined __CYGWIN__
#define PATHSEP "\\"
#define PATHSEPCHAR '\\'
#else
#define PATHSEP "/"
#define PATHSEPCHAR '/'
#endif

// CRY is easier to find than printf vs sprintf
#define CRY printf

#define WARN( msg ) perror( buildstringn( 5, msg, " ", __FILE__, " line ", __LINE__ ) )

int make_path( char *path );
int filecount( char *directory );
int filesize( char *file );
char * buildstring(int str_count,...);
char * buildstringn(int str_count,...);
char * buildstringns(int str_count,...);

// not sure if the linked list stuff is useful
typedef struct LinkedList {
  void * item;
  struct LinkedList * next;
  struct LinkedList * prev;
  struct LinkedList * head;
} LinkedList;

LinkedList * create_linked_list( void * item );
LinkedList * insert_next( LinkedList *list, void * item);
LinkedList * insert_prev( LinkedList *list, void * item);
void         free_linked_list( LinkedList *list, int free_items );
LinkedList * find_in_list( LinkedList *list, void * item );

#endif
