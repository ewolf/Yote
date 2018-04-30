#ifndef _UTIL_SEEN
#define _UTIL_SEEN

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

#define CRY printf

typedef struct {
  void * item;
  void * next;
  void * prev;
} LinkedList;

int make_path( char *path );
int filecount( char *directory );
int filesize( char *file );

LinkedList * create_linked_list( void * item );
LinkedList * set_next( LinkedList *list, void * item);
LinkedList * set_prev( LinkedList *list, void * item);
LinkedList * insert_next( LinkedList *list, void * item);
LinkedList * insert_prev( LinkedList *list, void * item);
void         cleanup_linked_list( LinkedList *list, int free_items );
#endif
