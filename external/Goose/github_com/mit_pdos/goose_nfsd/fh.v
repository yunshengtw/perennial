(* autogenerated from github.com/mit-pdos/goose-nfsd/fh *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.

From Goose Require github_com.mit_pdos.goose_nfsd.common.
From Goose Require github_com.mit_pdos.goose_nfsd.nfstypes.
From Goose Require github_com.tchajed.marshal.

Module Fh.
  Definition S := struct.decl [
    "Ino" :: uint64T;
    "Gen" :: uint64T
  ].
End Fh.

Definition MakeFh: val :=
  rec: "MakeFh" "fh3" :=
    let: "dec" := marshal.NewDec (struct.get nfstypes.Nfs_fh3.S "Data" "fh3") in
    let: "i" := marshal.Dec__GetInt "dec" in
    let: "g" := marshal.Dec__GetInt "dec" in
    struct.mk Fh.S [
      "Ino" ::= "i";
      "Gen" ::= "g"
    ].

Definition Fh__MakeFh3: val :=
  rec: "Fh__MakeFh3" "fh" :=
    let: "enc" := marshal.NewEnc #16 in
    marshal.Enc__PutInt "enc" (struct.get Fh.S "Ino" "fh");;
    marshal.Enc__PutInt "enc" (struct.get Fh.S "Gen" "fh");;
    let: "fh3" := struct.mk nfstypes.Nfs_fh3.S [
      "Data" ::= marshal.Enc__Finish "enc"
    ] in
    "fh3".

Definition MkRootFh3: val :=
  rec: "MkRootFh3" <> :=
    let: "enc" := marshal.NewEnc #16 in
    marshal.Enc__PutInt "enc" common.ROOTINUM;;
    marshal.Enc__PutInt "enc" #1;;
    struct.mk nfstypes.Nfs_fh3.S [
      "Data" ::= marshal.Enc__Finish "enc"
    ].

Definition Equal: val :=
  rec: "Equal" "h1" "h2" :=
    (if: slice.len (struct.get nfstypes.Nfs_fh3.S "Data" "h1") ≠ slice.len (struct.get nfstypes.Nfs_fh3.S "Data" "h2")
    then #false
    else
      let: "equal" := ref_to boolT #true in
      ForSlice byteT "i" "x" (struct.get nfstypes.Nfs_fh3.S "Data" "h1")
        (if: "x" ≠ SliceGet byteT (struct.get nfstypes.Nfs_fh3.S "Data" "h2") "i"
        then
          "equal" <-[boolT] #false;;
          Break
        else #());;
      ![boolT] "equal").
