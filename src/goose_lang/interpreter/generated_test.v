(* autogenerated by goose/cmd/test_gen *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.
From Perennial.goose_lang.interpreter Require Import test_config.

(* test functions *)
From Perennial.goose_lang.examples Require Import goose_semantics.

(* comparisons.go *)
Example testCompareAll_ok : testCompareAll #() ~~> #true := t.
Example testCompareGT_ok : testCompareGT #() ~~> #true := t.
Example testCompareGE_ok : testCompareGE #() ~~> #true := t.
Example testCompareLT_ok : testCompareLT #() ~~> #true := t.
Example testCompareLE_ok : testCompareLE #() ~~> #true := t.

(* conversions.go *)
Example testByteSliceToString_ok : testByteSliceToString #() ~~> #true := t.

(* copy.go *)
Example testCopySimple_ok : testCopySimple #() ~~> #true := t.
Example testCopyShorterDst_ok : testCopyShorterDst #() ~~> #true := t.
Example testCopyShorterSrc_ok : testCopyShorterSrc #() ~~> #true := t.

(* encoding.go *)
Example testEncDec32Simple_ok : testEncDec32Simple #() ~~> #true := t.
Fail Example testEncDec32_ok : failing_testEncDec32 #() ~~> #true := t.
Example testEncDec64Simple_ok : testEncDec64Simple #() ~~> #true := t.
Example testEncDec64_ok : testEncDec64 #() ~~> #true := t.

(* function_ordering.go *)
Fail Example testFunctionOrdering_ok : failing_testFunctionOrdering #() ~~> #true := t.

(* lock.go *)
Example testsUseLocks_ok : testsUseLocks #() ~~> #true := t.

(* loops.go *)
Example testStandardForLoop_ok : testStandardForLoop #() ~~> #true := t.
Example testForLoopWait_ok : testForLoopWait #() ~~> #true := t.
Example testBreakFromLoopWithContinue_ok : testBreakFromLoopWithContinue #() ~~> #true := t.
Fail Example testBreakFromLoopNoContinue_ok : failing_testBreakFromLoopNoContinue #() ~~> #true := t.
Example testNestedLoops_ok : testNestedLoops #() ~~> #true := t.
Example testNestedGoStyleLoops_ok : testNestedGoStyleLoops #() ~~> #true := t.

(* maps.go *)
Example testIterateMap_ok : testIterateMap #() ~~> #true := t.
Example testMapSize_ok : testMapSize #() ~~> #true := t.

(* nil.go *)
Fail Example testCompareSliceToNil_ok : failing_testCompareSliceToNil #() ~~> #true := t.
Example testComparePointerToNil_ok : testComparePointerToNil #() ~~> #true := t.
Example testCompareNilToNil_ok : testCompareNilToNil #() ~~> #true := t.

(* operations.go *)
Example testReverseAssignOps64_ok : testReverseAssignOps64 #() ~~> #true := t.
Fail Example testReverseAssignOps32_ok : failing_testReverseAssignOps32 #() ~~> #true := t.
Example testAdd64Equals_ok : testAdd64Equals #() ~~> #true := t.
Example testSub64Equals_ok : testSub64Equals #() ~~> #true := t.
Example testDivisionPrecedence_ok : testDivisionPrecedence #() ~~> #true := t.
Example testModPrecedence_ok : testModPrecedence #() ~~> #true := t.
Example testBitwiseOpsPrecedence_ok : testBitwiseOpsPrecedence #() ~~> #true := t.
Example testArithmeticShifts_ok : testArithmeticShifts #() ~~> #true := t.

(* precedence.go *)
Example testOrCompareSimple_ok : testOrCompareSimple #() ~~> #true := t.
Example testOrCompare_ok : testOrCompare #() ~~> #true := t.
Example testAndCompare_ok : testAndCompare #() ~~> #true := t.

(* prims.go *)
Example testLinearize_ok : testLinearize #() ~~> #true := t.

(* shortcircuiting.go *)
Example testShortcircuitAndTF_ok : testShortcircuitAndTF #() ~~> #true := t.
Example testShortcircuitAndFT_ok : testShortcircuitAndFT #() ~~> #true := t.
Example testShortcircuitOrTF_ok : testShortcircuitOrTF #() ~~> #true := t.
Example testShortcircuitOrFT_ok : testShortcircuitOrFT #() ~~> #true := t.

(* slices.go *)
Example testSliceOps_ok : testSliceOps #() ~~> #true := t.
Example testOverwriteArray_ok : testOverwriteArray #() ~~> #true := t.

(* strings.go *)
Fail Example testStringAppend_ok : failing_testStringAppend #() ~~> #true := t.
Fail Example testStringLength_ok : failing_testStringLength #() ~~> #true := t.

(* structs.go *)
Fail Example testStructUpdates_ok : failing_testStructUpdates #() ~~> #true := t.
Example testNestedStructUpdates_ok : testNestedStructUpdates #() ~~> #true := t.
Example testStructConstructions_ok : testStructConstructions #() ~~> #true := t.
Example testStoreInStructVar_ok : testStoreInStructVar #() ~~> #true := t.
Example testStoreInStructPointerVar_ok : testStoreInStructPointerVar #() ~~> #true := t.
Example testStoreComposite_ok : testStoreComposite #() ~~> #true := t.
Example testStoreSlice_ok : testStoreSlice #() ~~> #true := t.

(* wal.go *)

