#ifndef _OBJ_STORE_SEEN
#define _OBJ_STORE_SEEN

#include "record_store.h"
#include "util.h"

#define OS_VERSION "1.0"

#define MAX_SILOS 100

typedef struct
{
  char        * directory;
  RecordStore * record_store;
} ObjectStore;

typedef struct
{

} Container;

ObjectStore * open_object_store( char *directory );
Container   * load_root_container( ObjectStore * store );

#endif
