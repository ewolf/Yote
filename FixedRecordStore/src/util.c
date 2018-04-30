#include "util.h"

/* like mkdir -p. Return 0 if success, 1 if cant, 2 if error making dir */
int
make_path( char *dirpath )
{
  struct stat stat_buffer;
  int i, len;
  char *path = strdup( dirpath );

  len = 1 + strlen( path );
  for( i=1; i<len; i++ )
    {
      if( path[i] == PATHSEPCHAR )
        {
          path[i] = '\0';
          if( 0 == stat( path, &stat_buffer ) )
            {
              if( ! S_ISDIR( stat_buffer.st_mode ) )
                {
                  // BAD, EXISTS AND IS NOT A DIRECTORY
                  path[i] = PATHSEPCHAR;
                  free( path );
                  return 1;
                }
            }
          else if( 0 != mkdir( path, 0775 ) )
            {
              perror( "make_path" );
              path[i] = PATHSEPCHAR;
              free( path );

              return 2;
            }
          path[i] = PATHSEPCHAR;
        }
      else if( path[i] == '\0' )
        {
          if( 0 == stat( path, &stat_buffer ) )
            {
              if( ! S_ISDIR( stat_buffer.st_mode ) )
                {
                  // BAD, EXISTS AND IS NOT A DIRECTORY
                  free( path );

                  return 1;
                }
            }
          else if( 0 != mkdir( path, 0775 ) )
            {
              perror( "make_path" );
              free( path );
              return 2;
            } // try to make the path
          free( path );
          return 0;
        }
    } //each i
  return 0;
} //make_path

int
rm_path( char *pathpart, char * rmpart )
{
  //  int i;
  char * path = malloc( 1 + strlen( pathpart ) + strlen( rmpart ) );
  strcat( path, pathpart );
  strcat( path, PATHSEP );
  strcat( path, rmpart );

  //  for( i=
  free( path );
  return 0;
} //rm_path

int
filecount( char *directory )
{
  int filecount = 0;
  DIR *d = opendir( directory );
  struct dirent *dir;
  
  if ( d ) {
    while ( NULL != (dir = readdir(d)) )
      {
        if( 0 != strcmp( dir->d_name, ".." ) && 0 != strcmp( dir->d_name, "." ) ) {
          filecount++;
        }
      }
    closedir(d);
  }
  
  return filecount;
} //filecount

int
filesize( char *file ) {
    struct stat statbuf;
    if( stat( file, &statbuf ) ) {
      perror( "filesize" );
    }
    return statbuf.st_size;
} //filesize

LinkedList *
create_linked_list( void * item )
{
  LinkedList * list;

  list = malloc( sizeof( LinkedList ) );
  list->item = item;
  list->next = NULL;
  list->prev = NULL;
  
  return list;
} //create_linked_list

LinkedList *
set_next( LinkedList * list, void * item )
{
  LinkedList * next = create_linked_list( item );
  list->next = next;
  next->prev = list;
  
  return next;
} //set_next

LinkedList *
set_prev( LinkedList * list, void * item )
{
  LinkedList * prev = create_linked_list( item );
  list->prev = prev;
  prev->next = list;
  
  return prev;
} //set_prev

LinkedList *
insert_next( LinkedList * list, void * item )
{
  LinkedList * next;
  LinkedList * new_next = create_linked_list( item );
  next           = list->next;
  list->next     = new_next;
  new_next->prev = list;
  
  if ( next )
    {
      next->prev     = new_next;
      new_next->next = next;
    }
  
  return new_next;
} //insert_next

LinkedList *
insert_prev( LinkedList * list, void * item )
{
  LinkedList * prev;
  LinkedList * new_prev = create_linked_list( item );
  prev           = list->prev;
  list->prev     = new_prev;
  new_prev->next = list;
  if ( prev )
    {
      prev->next     = new_prev;
      new_prev->prev = prev;
    }
  
  return new_prev;
} //insert_prev

void
free_linked_list( LinkedList *list, int free_items )
{
  LinkedList * l;
  if ( free_items && list->item )
    {
      free( list->item );
      list->item = NULL;
    }
  if ( (l = list->next) )
    {
      list->next = NULL;
      l->prev = NULL;
      free_linked_list( l, free_items );
      
    }
  if ( (l = list->prev) )
    {
      list->prev = NULL;
      l->next = NULL;
      free_linked_list( l, free_items );
    }
  free( list );
} //free_linked_list
