/* Copyright (c) 2013-2026 Mahmoud Fayed <msfclipper@yahoo.com> */

#include "ring.h"

void ring_vm_try(VM *pVM) {
  List *pList;
  pList = ring_list_newlist_gc(pVM->pRingState, pVM->pTry);
  ring_list_addint_gc(pVM->pRingState, pList, RING_VM_IR_READI);
  ring_list_addint_gc(pVM->pRingState, pList, pVM->nInsideEval);
  ring_vm_savestate(pVM, pList);
  pVM->lActiveCatch = RING_FALSE;
}

void ring_vm_catch(VM *pVM, const char *cError) {
  List *pList;
  char cFullError[RING_LARGEBUF];
  int nLine;
  const char *cFile;

  pList = ring_list_getlist(pVM->pTry, ring_list_getsize(pVM->pTry));
  pVM->nPC = ring_list_getint(pList, RING_TRY_PC);
  pVM->nInsideEval = ring_list_getint(pList, RING_TRY_INSIDEEVAL);

  /* Extract active line number and source file */
  nLine = (int)RING_VM_IR_GETLINENUMBER;
  cFile = pVM->cFileName ? pVM->cFileName : "";

  /* Format contextual error message: Line %d %s in %s */
  if (cError && strncmp(cError, "Line ", 5) == 0) {
    strncpy(cFullError, cError, sizeof(cFullError) - 1);
    cFullError[sizeof(cFullError) - 1] = '\0';
  } else if (cFile && cFile[0]) {
    snprintf(cFullError, sizeof(cFullError), "Line %d %s in %s", nLine,
             cError ? cError : "", cFile);
  } else {
    snprintf(cFullError, sizeof(cFullError), "Line %d %s", nLine,
             cError ? cError : "");
  }

  /* Set the cCatchError variable to contain the contextual error message */
  RING_VAR_SETSTRING_GC(pVM->pRingState, pVM->pErrorMsg, cFullError);
  /* Avoid invalidated cError (variable) content by restore */
  ring_vm_restorestate(pVM, pList, RING_TRY_STATE, RING_STATE_TRYCATCH);
  /* Tell C-API caller (CALL command) that catch happens! */
  pVM->lActiveCatch = RING_TRUE;
  /* Catch Statements must be executed without try effects */
  ring_vm_done(pVM);
}

void ring_vm_done(VM *pVM) {
  ring_list_deleteitem_gc(pVM->pRingState, pVM->pTry,
                          ring_list_getsize(pVM->pTry));
}
