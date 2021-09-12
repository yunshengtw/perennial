From Perennial.Helpers Require Import List.

From Goose.github_com.tchajed Require Import marshal.
From Perennial.goose_lang.lib Require Import encoding.

From Perennial.program_proof Require Import proof_prelude.
From Perennial.goose_lang.lib Require Import slice.typed_slice.

Inductive encodable :=
| EncUInt64 (x:u64)
| EncUInt32 (x:u32)
| EncBytes (bs:list u8)
| EncBool (b:bool)
.

Definition Rec := list encodable.

Local Definition encode1 (e:encodable) : list u8 :=
  match e with
  | EncUInt64 x => u64_le x
  | EncUInt32 x => u32_le x
  | EncBytes bs => bs
  | EncBool b => [U8 (if b then 1 else 0)%Z]
  end.

Lemma encode1_u64_inj : Inj (=) (=) (encode1 ∘ EncUInt64).
Proof.
  move=>x y /= Heq.
  rewrite -(u64_le_to_word x).
  rewrite -(u64_le_to_word y).
  rewrite Heq //.
Qed.
Lemma encode1_u32_inj : Inj (=) (=) (encode1 ∘ EncUInt32).
Proof.
  move=>x y /= Heq.
  rewrite -(u32_le_to_word x).
  rewrite -(u32_le_to_word y).
  rewrite Heq //.
Qed.
Lemma encode1_bytes_inj : Inj (=) (=) (encode1 ∘ EncBytes).
Proof. move=>x y /= Heq //. Qed.
Lemma encode1_bool_inj : Inj (=) (=) (encode1 ∘ EncBool).
Proof.
  move=>x y /= Heq.
  by destruct x, y.
Qed.

Lemma encode1_bytes_len bs : length (encode1 (EncBytes bs)) = length bs.
Proof. done. Qed.

Local Definition encode (es:Rec): list u8 := concat (encode1 <$> es).

Notation encoded_length r := (length (encode r)).

Theorem encode_app es1 es2 :
  encode (es1 ++ es2) = encode es1 ++ encode es2.
Proof.
  rewrite /encode.
  rewrite fmap_app.
  rewrite concat_app //.
Qed.

Theorem encode_singleton x :
  encode [x] = encode1 x.
Proof.
  rewrite /encode /=.
  rewrite app_nil_r //.
Qed.

Theorem encode_cons x xs :
  encode (x::xs) = encode1 x ++ encode xs.
Proof.
  change (?x::?xs) with ([x] ++ xs).
  rewrite encode_app encode_singleton //.
Qed.

Theorem encoded_length_singleton x :
  encoded_length [x] = length (encode1 x).
Proof. rewrite encode_singleton //. Qed.

Theorem encoded_length_app (r1 r2:Rec) :
  encoded_length (r1 ++ r2) = (encoded_length r1 + encoded_length r2)%nat.
Proof. rewrite encode_app; len. Qed.

Theorem encoded_length_app1 (r:Rec) (x:encodable) :
  encoded_length (r ++ [x]) = (encoded_length r + length (encode1 x))%nat.
Proof. rewrite encoded_length_app encoded_length_singleton //. Qed.

(** has_encoding is an opaque connection between data and a typed record

    It is generated by encoding [r] with an [Enc] and calling [Enc__Finish], and
    is subsequently used while decoding to reconstruct [r]. *)
Definition has_encoding (data: list u8) (r:Rec) :=
  take (encoded_length r) data = encode r.

Typeclasses Opaque has_encoding.

Lemma has_encoding_length {data r} :
  has_encoding data r →
  (encoded_length r ≤ length data)%nat.
Proof.
  intros H%(f_equal length).
  move: H; len.
Qed.

Lemma has_encoding_app_characterization data r :
  has_encoding data r ↔
  ∃ extra, data = encode r ++ extra.
Proof.
  split; intros.
  - rewrite /has_encoding in H.
    exists (drop (encoded_length r) data).
    rewrite -[data in data = _](take_drop (encoded_length r)) H //.
  - destruct H as [extra ->].
    rewrite /has_encoding.
    rewrite take_app_le //.
    rewrite take_ge //.
Qed.

Lemma has_encoding_inv data r :
  has_encoding data r →
  ∃ extra, data = encode r ++ extra ∧
           (encoded_length r + length extra = length data)%nat.
Proof.
  intros [extra ->]%has_encoding_app_characterization.
  exists extra; intuition.
  len.
Qed.

Lemma has_encoding_from_app data extra r :
  data = encode r ++ extra →
  has_encoding data r.
Proof.
  intros ->.
  apply has_encoding_app_characterization; eauto.
Qed.

Section goose_lang.
Context `{hG: heapGS Σ, !ffi_semantics _ _, !ext_types _}.

Implicit Types (v:val).

Definition is_enc (enc_v:val) (sz:Z) (r: Rec) (remaining: Z) : iProp Σ :=
  ∃ (s: Slice.t) (off_l: loc) (data: list u8),
    let off := encoded_length r in
    "->" ∷ ⌜enc_v = (slice_val s, (#off_l, #()))%V⌝ ∗
    "Hs" ∷ is_slice_small s byteT 1 data ∗
    "Hs_cap" ∷ is_slice_cap s byteT ∗
    "%Hsz" ∷ ⌜length data = Z.to_nat sz⌝ ∗
    "%Hremaining" ∷ ⌜(off + remaining)%Z = sz⌝ ∗
    "Hoff" ∷ off_l ↦[uint64T] #off ∗
    "%Hoff" ∷ ⌜0 ≤ off ≤ length data⌝ ∗
    "%Hencoded" ∷ ⌜has_encoding data r⌝
.

Theorem wp_new_enc stk E (sz: u64) :
  {{{ True }}}
    NewEnc #sz @ stk; E
  {{{ (enc_v:val), RET enc_v; is_enc enc_v (int.Z sz) [] (int.Z sz) }}}.
Proof.
  iIntros (Φ) "_ HΦ".
  wp_call.
  wp_apply (wp_NewSlice (V:=u8)).
  iIntros (s) "Hs".
  iDestruct (is_slice_split with "Hs") as "[Hs Hcap]".
  wp_apply (typed_mem.wp_AllocAt uint64T); eauto.
  iIntros (off_l) "Hoff".
  wp_pures.
  iApply "HΦ".
  iExists _, _, _; iFrame.
  iPureIntro.
  split_and!; auto; len.
  rewrite /has_encoding //.
Qed.

Lemma has_encoding_app data r data' r' :
  has_encoding data r →
  has_encoding data' r' →
  has_encoding (take (encoded_length r) data ++ data')
                (r ++ r').
Proof.
  intros Hdata Hdata'.
  rewrite Hdata.
  apply has_encoding_inv in Hdata' as [extra' [-> _]].
  rewrite app_assoc.
  eapply has_encoding_from_app.
  rewrite encode_app -!app_assoc //.
Qed.

Theorem wp_Enc__PutInt stk E enc_v sz r (x:u64) remaining :
  8 ≤ remaining →
  {{{ is_enc enc_v sz r remaining }}}
    Enc__PutInt enc_v #x @ stk; E
  {{{ RET #(); is_enc enc_v sz (r ++ [EncUInt64 x]) (remaining - 8) }}}.
Proof.
  iIntros (Hspace Φ) "Hpre HΦ"; iNamed "Hpre".
  set (off:=encoded_length r) in *.
  wp_call.
  wp_load.
  wp_pures.
  iDestruct (is_slice_small_sz with "Hs") as %Hslice_len.
  wp_apply wp_SliceSkip'.
  { iPureIntro.
    word. }
  iDestruct (is_slice_small_take_drop _ _ _ (U64 off) with "Hs") as "[Hs2 Hs1]".
  { word. }
  replace (int.nat (U64 off)) with off by word.
  wp_apply (wp_UInt64Put with "[$Hs2]").
  { iPureIntro.
    len. }
  iIntros "Hs2".
  iDestruct (slice.is_slice_combine with "Hs1 Hs2") as "Hs"; first len.
  wp_pures.
  wp_load; wp_store.
  rewrite -fmap_drop drop_drop.
  iApply "HΦ".
  iExists _, _, _; iFrame.
  change (u64_le_bytes x) with (into_val.to_val (V:=u8) <$> u64_le x).
  rewrite -!fmap_app.
  iSplitR; first eauto.
  iFrame "Hs". iModIntro.
  rewrite encoded_length_app1.
  change (length (encode1 (EncUInt64 x))) with 8%nat.
  iSplitR; first by iPureIntro; len.
  iSplitR; first by iPureIntro; len.
  iSplitL "Hoff".
  { iExactEq "Hoff".
    rewrite /named.
    repeat (f_equal; try word). }
  iPureIntro; split.
  - len.
  - subst off.
    apply has_encoding_app; auto.
    eapply has_encoding_from_app; eauto.
Qed.

Theorem wp_Enc__PutInt32 stk E enc_v sz r (x:u32) remaining :
  4 ≤ remaining →
  {{{ is_enc enc_v sz r remaining }}}
    Enc__PutInt32 enc_v #x @ stk; E
  {{{ RET #(); is_enc enc_v sz (r ++ [EncUInt32 x]) (remaining - 4) }}}.
Proof.
  iIntros (Hspace Φ) "Hpre HΦ"; iNamed "Hpre".
  set (off:=encoded_length r) in *.
  wp_call.
  wp_load.
  wp_pures.
  iDestruct (is_slice_small_sz with "Hs") as %Hslice_len.
  wp_apply wp_SliceSkip'.
  { iPureIntro.
    word. }
  iDestruct (is_slice_small_take_drop _ _ _ (U64 off) with "Hs") as "[Hs2 Hs1]".
  { word. }
  replace (int.nat (U64 off)) with off by word.
  wp_apply (wp_UInt32Put with "[$Hs2]").
  { iPureIntro.
    len. }
  iIntros "Hs2".
  iDestruct (slice.is_slice_combine with "Hs1 Hs2") as "Hs"; first len.
  wp_pures.
  wp_load; wp_store.
  rewrite -fmap_drop drop_drop.
  iApply "HΦ".
  iExists _, _, _; iFrame.
  change (u32_le_bytes x) with (into_val.to_val <$> u32_le x).
  rewrite -!fmap_app.
  iSplitR; first eauto.
  iFrame "Hs". iModIntro.
  rewrite encoded_length_app1.
  change (length (encode1 _)) with 4%nat.
  iSplitR; first by iPureIntro; len.
  iSplitR; first by iPureIntro; len.
  iSplitL "Hoff".
  { iExactEq "Hoff".
    rewrite /named.
    repeat (f_equal; try word). }
  iPureIntro; split.
  - len.
  - subst off.
    apply has_encoding_app; auto.
    eapply has_encoding_from_app; eauto.
Qed.

Local Lemma wp_bool2byte stk E (x:bool) :
  {{{ True }}}
    bool2byte #x @ stk; E
  {{{ RET #(U8 (if x then 1 else 0))%Z; True }}}.
Proof.
  iIntros (Φ) "_ HΦ". wp_lam.
  destruct x; wp_pures; by iApply "HΦ".
Qed.

Theorem wp_Enc__PutBool stk E enc_v sz r (x:bool) remaining :
  1 ≤ remaining →
  {{{ is_enc enc_v sz r remaining }}}
    Enc__PutBool enc_v #x @ stk; E
  {{{ RET #(); is_enc enc_v sz (r ++ [EncBool x]) (remaining - 1) }}}.
Proof.
  iIntros (Hspace Φ) "Hpre HΦ"; iNamed "Hpre".
  set (off:=encoded_length r) in *.
  wp_call.
  wp_load.
  wp_pures.
  iDestruct (is_slice_small_sz with "Hs") as %Hslice_len.
  wp_pures.
  wp_apply wp_bool2byte.
  set (u:=U8 (if x then 1 else 0)%Z).
  wp_pures.
  wp_apply (wp_SliceSet (V:=byte) with "[$Hs]").
  { iPureIntro. apply lookup_lt_is_Some_2. word. }
  iIntros "Hs".
  wp_pures.
  wp_load. wp_store.
  iApply "HΦ". iModIntro.
  iExists _, _, _. iFrame.
  iSplit; eauto.
  rewrite insert_length.
  iSplit; eauto.
  rewrite encoded_length_app1. simpl.
  iSplit.
  { iPureIntro. word. }
  iSplit.
  { iExactEq "Hoff". rewrite /named. do 3 f_equal. word. }
  iPureIntro.
  split; first word.
  replace (<[int.nat off:=u]> data) with
      (take off data ++ [u] ++ drop (off + 1) data); last first.
  { rewrite insert_take_drop. 2:word.
    repeat f_equal; word. }
  apply has_encoding_app; eauto.
  eapply has_encoding_from_app; eauto.
Qed.

Theorem wp_Enc__PutInts stk E enc_v sz r (x_s: Slice.t) q (xs:list u64) remaining :
  8*(Z.of_nat $ length xs) ≤ remaining →
  {{{ is_enc enc_v sz r remaining ∗ is_slice_small x_s uint64T q xs }}}
    Enc__PutInts enc_v (slice_val x_s) @ stk; E
  {{{ RET #(); is_enc enc_v sz (r ++ (EncUInt64 <$> xs)) (remaining - 8*(Z.of_nat $ length xs)) ∗
               is_slice_small x_s uint64T q xs }}}.
Proof.
  iIntros (Hbound Φ) "[Henc Hxs] HΦ".
  wp_rec; wp_pures.
  wp_apply (wp_forSlicePrefix
              (λ done todo,
                "Henc" ∷ is_enc enc_v sz
                        (r ++ (EncUInt64 <$> done))
                        (remaining - 8*(Z.of_nat $ length done)))%I
           with "[] [$Hxs Henc]").
  - clear Φ.
    iIntros (???? Hdonetodo) "!>".
    iIntros (Φ) "HI HΦ"; iNamed "HI".
    wp_pures.
    wp_apply (wp_Enc__PutInt with "Henc").
    { apply (f_equal length) in Hdonetodo; move: Hdonetodo; len. }
    iIntros "Henc".
    iApply "HΦ".
    iExactEq "Henc".
    rewrite /named; f_equal; len.
    rewrite fmap_app.
    rewrite -!app_assoc.
    reflexivity.
  - iExactEq "Henc".
    rewrite /named; f_equal; len.
    rewrite app_nil_r //.
  - iIntros "(Hs&HI)"; iNamed "HI".
    iApply "HΦ"; by iFrame.
Qed.

Hint Rewrite encoded_length_app1 : len.

Theorem wp_Enc__PutBytes stk E enc_v r sz remaining b_s q bs :
  Z.of_nat (length bs) ≤ remaining →
  {{{ is_enc enc_v sz r remaining ∗ is_slice_small b_s byteT q bs }}}
    Enc__PutBytes enc_v (slice_val b_s) @ stk; E
  {{{ RET #(); is_enc enc_v sz (r ++ [EncBytes bs]) (remaining - Z.of_nat (length bs)) ∗
               is_slice_small b_s byteT q bs }}}.
Proof.
  iIntros (Hbound Φ) "[Henc Hbs] HΦ"; iNamed "Henc".
  wp_call.
  wp_load; wp_pures.
  iDestruct (is_slice_small_sz with "Hs") as %Hs_sz.
  wp_apply wp_SliceSkip'.
  { iPureIntro; len. }
  iDestruct (slice_small_split _ (U64 (encoded_length r)) with "Hs") as "[Hs1 Hs2]"; first by len.
  wp_apply (wp_SliceCopy (V:=byte) with "[$Hbs $Hs2]"); first by len.
  iIntros "[Hbs Hs2]".
  iDestruct (is_slice_combine with "Hs1 Hs2") as "Hs"; first by len.
  wp_pures.
  wp_load; wp_store.
  iApply "HΦ".
  iFrame. iModIntro.
  iExists _, _, _; iFrame.
  iSplitR; first by eauto.
  iSplitR.
  { iPureIntro; len. }
  iSplitR.
  { iPureIntro; len. simpl; len. }
  iSplitL "Hoff".
  { iExactEq "Hoff".
    rewrite /named.
    f_equal.
    f_equal.
    f_equal.
    len.
    simpl.
    word.
  }
  iPureIntro.
  split_and.
  - len.
    simpl; len.
  - replace (int.nat (U64 (encoded_length r))) with (encoded_length r) by word.
    rewrite Hencoded.
    rewrite app_assoc.
    eapply has_encoding_from_app.
    rewrite encode_app encode_singleton //=.
Qed.

Theorem wp_Enc__Finish stk E enc_v r sz remaining :
  {{{ is_enc enc_v sz r remaining }}}
    Enc__Finish enc_v @ stk; E
  {{{ s data, RET slice_val s; ⌜has_encoding data r⌝ ∗
                               ⌜length data = Z.to_nat sz⌝ ∗
                               is_slice s byteT 1 data }}}.
Proof.
  iIntros (Φ) "Henc HΦ"; iNamed "Henc"; subst.
  wp_call.
  iApply "HΦ"; by iFrame "∗ %".
Qed.

Definition is_dec (dec_v:val) (r:Rec) (s:Slice.t) (q:Qp) (data: list u8): iProp Σ :=
  ∃ (off_l:loc) (off: u64),
    "->" ∷ ⌜dec_v = (slice_val s, (#off_l, #()))%V⌝ ∗
    "Hoff" ∷ off_l ↦[uint64T] #off ∗
    "%Hoff" ∷ ⌜int.nat off ≤ length data⌝ ∗
    "Hs" ∷ is_slice_small s byteT q data ∗
    "%Henc" ∷ ⌜has_encoding (drop (int.nat off) data) r⌝.

Lemma is_dec_to_is_slice_small dec_v r s q data :
  is_dec dec_v r s q data -∗
  is_slice_small s byteT q data.
Proof.
  iIntros "H". iNamed "H". iFrame.
Qed.

Theorem wp_new_dec stk E s q data r :
  has_encoding data r →
  {{{ is_slice_small s byteT q data }}}
    NewDec (slice_val s) @ stk; E
  {{{ dec_v, RET dec_v; is_dec dec_v r s q data }}}.
Proof.
  iIntros (Henc Φ) "Hs HΦ".
  wp_call.
  wp_apply (typed_mem.wp_AllocAt uint64T); eauto.
  iIntros (off_l) "Hoff".
  wp_pures.
  iApply "HΦ".
  iExists _, _; iFrame.
  iPureIntro.
  split_and!; auto; len.
Qed.

Hint Rewrite encoded_length_singleton : len.

Lemma encoded_length_cons x r :
  encoded_length (x::r) = (length (encode1 x) + encoded_length r)%nat.
Proof. rewrite encode_cons; len. Qed.

Theorem wp_Dec__GetInt stk E dec_v (x: u64) r s q data :
  {{{ is_dec dec_v (EncUInt64 x :: r) s q data }}}
    Dec__GetInt dec_v @ stk; E
  {{{ RET #x; is_dec dec_v r s q data }}}.
Proof.
  iIntros (Φ) "Hdec HΦ"; iNamed "Hdec".
  wp_call.
  wp_load; wp_pures.
  wp_load; wp_store.
  iDestruct (is_slice_small_sz with "Hs") as %Hsz.
  wp_apply wp_SliceSkip'.
  { iPureIntro; word. }
  iDestruct (slice.slice_small_split _ off with "Hs") as "[Hs1 Hs2]".
  { len. }
  wp_apply (wp_UInt64Get_unchanged with "Hs2").
  { eapply has_encoding_inv in Henc as [extra [Henc ?]].
    rewrite -fmap_drop -fmap_take.
    rewrite Henc.
    reflexivity. }
  iIntros "Hs2".
  iDestruct (slice.is_slice_small_take_drop_1 with "[$Hs1 $Hs2]") as "Hs"; first by word.
  iApply "HΦ".
  iExists _, _; iFrame.
  iSplitR; first by auto.
  pose proof (has_encoding_length Henc).
  autorewrite with len in H.
  rewrite encoded_length_cons in H.
  change (length (encode1 _)) with 8%nat in H.
  iSplitR; first iPureIntro.
  { word. }
  iPureIntro.
  replace (int.nat (word.add off 8)) with (int.nat off + 8)%nat by word.
  rewrite -drop_drop.
  apply has_encoding_inv in Henc as [extra [Henc ?]].
  rewrite Henc.
  rewrite encode_cons.
  eapply has_encoding_from_app.
  rewrite -app_assoc.
  rewrite drop_app_ge //.
Qed.

Theorem wp_Dec__GetInt32 stk E dec_v (x: u32) r s q data :
  {{{ is_dec dec_v (EncUInt32 x :: r) s q data }}}
    Dec__GetInt32 dec_v @ stk; E
  {{{ RET #x; is_dec dec_v r s q data }}}.
Proof.
  iIntros (Φ) "Hdec HΦ"; iNamed "Hdec".
  wp_call.
  wp_load; wp_pures.
  wp_load; wp_store.
  iDestruct (is_slice_small_sz with "Hs") as %Hsz.
  wp_apply wp_SliceSkip'.
  { iPureIntro; word. }
  iDestruct (slice.slice_small_split _ off with "Hs") as "[Hs1 Hs2]".
  { len. }
  wp_apply (wp_UInt32Get_unchanged with "Hs2").
  { eapply has_encoding_inv in Henc as [extra [Henc ?]].
    rewrite -fmap_drop -fmap_take.
    rewrite Henc.
    reflexivity. }
  iIntros "Hs2".
  iDestruct (slice.is_slice_small_take_drop_1 with "[$Hs1 $Hs2]") as "Hs"; first by word.
  iApply "HΦ".
  iExists _, _; iFrame.
  iSplitR; first by auto.
  pose proof (has_encoding_length Henc).
  autorewrite with len in H.
  rewrite encoded_length_cons in H.
  change (length (encode1 _)) with 4%nat in H.
  iSplitR; first iPureIntro.
  { word. }
  iPureIntro.
  replace (int.nat (word.add off 4)) with (int.nat off + 4)%nat by word.
  rewrite -drop_drop.
  apply has_encoding_inv in Henc as [extra [Henc ?]].
  rewrite Henc.
  rewrite encode_cons.
  eapply has_encoding_from_app.
  rewrite -app_assoc.
  rewrite drop_app_ge //.
Qed.

Theorem wp_Dec__GetBool stk E dec_v (x: bool) r s q data :
  {{{ is_dec dec_v (EncBool x :: r) s q data }}}
    Dec__GetBool dec_v @ stk; E
  {{{ RET #x; is_dec dec_v r s q data }}}.
Proof.
  iIntros (Φ) "Hdec HΦ"; iNamed "Hdec".
  wp_call.
  wp_load; wp_pures.
  wp_load; wp_store.
  iDestruct (is_slice_small_sz with "Hs") as %Hsz.
  pose proof (has_encoding_length Henc).
  autorewrite with len in H.
  rewrite encoded_length_cons in H.
  change (length (encode1 _)) with 1%nat in H.
  apply has_encoding_inv in Henc as [extra [Henc ?]].
  rewrite encode_cons in Henc.
  assert (drop (int.nat off) data !! 0%nat = Some $ U8 (if x then 1 else 0)) as Hx.
  { rewrite Henc. done. }
  rewrite lookup_drop Nat.add_0_r in Hx.
  wp_apply (wp_SliceGet (V:=byte) with "[$Hs]").
  { done. }
  iIntros "Hl". wp_pures.
  destruct x; wp_pures; iApply "HΦ";
    iExists _, _; iFrame; iPureIntro.
  - split; first done.
    split; first word.
    eapply has_encoding_from_app.
    replace (int.nat (word.add off 1)) with (int.nat off + 1)%nat by word.
    rewrite -drop_drop.
    rewrite Henc /= drop_0 //.
  - split; first done.
    split; first word.
    eapply has_encoding_from_app.
    replace (int.nat (word.add off 1)) with (int.nat off + 1)%nat by word.
    rewrite -drop_drop.
    rewrite Henc /= drop_0 //.
Qed.

(* This version of GetBytes consumes full ownership of the decoder to be able to
   give the full fraction to the returned slice *)
Theorem wp_Dec__GetBytes' stk E dec_v bs (n: u64) r s q data :
  n = U64 (length bs) →
  {{{ is_dec dec_v (EncBytes bs :: r) s q data ∗
      (∀ vs' : list u8, is_slice_small s byteT q vs' -∗ is_slice s byteT q vs') }}}
    Dec__GetBytes dec_v #n @ stk; E
  {{{ s', RET slice_val s'; is_slice s' byteT q bs }}}.
Proof.
  iIntros (-> Φ) "(Hdec&Hclo) HΦ"; iNamed "Hdec".
  pose proof (has_encoding_length Henc).
  autorewrite with len in H.
  rewrite encoded_length_cons /= in H.
  wp_call.
  wp_load.
  iDestruct (is_slice_small_sz with "Hs") as %Hsz.
  wp_pures.
  iDestruct ("Hclo" with "[$]") as "Hs".
  wp_apply (wp_SliceSubslice_drop_rest' with "Hs"); first by word.
  iIntros (s') "Hbs".
  wp_pures.
  wp_load; wp_store.
  iApply "HΦ". iModIntro.
  apply has_encoding_inv in Henc as [extra [Hdataeq _]].
  rewrite encode_cons /= -app_assoc in Hdataeq.
  iExactEq "Hbs".
  f_equal.
  rewrite -> subslice_drop_take by word.
  replace (int.nat (word.add off (length bs)) - int.nat off)%nat with (length bs) by word.
  rewrite Hdataeq.
  rewrite take_app_alt //; lia.
Qed.

Theorem wp_Dec__GetBytes stk E dec_v bs (n: u64) r s q data :
  n = U64 (length bs) →
  {{{ is_dec dec_v (EncBytes bs :: r) s q data }}}
    Dec__GetBytes dec_v #n @ stk; E
  {{{ q' s', RET slice_val s'; is_slice_small s' byteT q' bs ∗ is_dec dec_v r s q' data }}}.
Proof.
  iIntros (-> Φ) "Hdec HΦ"; iNamed "Hdec".
  pose proof (has_encoding_length Henc).
  autorewrite with len in H.
  rewrite encoded_length_cons /= in H.
  wp_call.
  wp_load.
  iDestruct (is_slice_small_sz with "Hs") as %Hsz.
  (* we split the decoder state into one half used to serve the client and one
     half to reconstruct the decoder (now with half the fraction) *)
  iDestruct (fractional.fractional_half with "Hs") as "[Hs1 Hs2]".
  wp_pures.
  wp_apply (wp_SliceSubslice_drop_rest with "Hs1"); first by word.
  iIntros (s') "Hbs".
  wp_pures.
  wp_load; wp_store.
  iApply "HΦ". iModIntro.
  apply has_encoding_inv in Henc as [extra [Hdataeq _]].
  rewrite encode_cons /= -app_assoc in Hdataeq.
  iSplitL "Hbs".
  { iExactEq "Hbs".
    f_equal.
    rewrite -> subslice_drop_take by word.
    replace (int.nat (word.add off (length bs)) - int.nat off)%nat with (length bs) by word.
    rewrite Hdataeq.
    rewrite take_app_alt //; lia.
  }
  iExists _, _; iFrame.
  iPureIntro.
  split_and!; auto; try len.
  replace (int.nat (word.add off (length bs))) with (int.nat off + int.nat (length bs))%nat by word.
  rewrite -drop_drop.
  eapply has_encoding_from_app.
  rewrite Hdataeq.
  rewrite drop_app_alt //; word.
Qed.

Theorem wp_Dec__GetBytes_ro stk E dec_v bs (n: u64) r s q data :
  n = U64 (length bs) →
  {{{ is_dec dec_v (EncBytes bs :: r) s q data }}}
    Dec__GetBytes dec_v #n @ stk; E
  {{{ q' s', RET slice_val s'; readonly (is_slice_small s' byteT 1 bs) ∗ is_dec dec_v r s q' data }}}.
Proof.
  iIntros (-> Φ) "Hdec HΦ".
  iApply wp_ncfupd.
  iApply (wp_Dec__GetBytes with "Hdec"); first done.
  iIntros "!>" (q' s') "[Hsl Hdec]".
  iApply "HΦ". iFrame "Hdec".
  iMod (readonly_alloc with "[Hsl]") as "$"; by iFrame.
Qed.

(* TODO: use this to replace list_lookup_lt (it's much easier to remember) *)
Local Tactic Notation "list_elem" constr(l) constr(i) "as" simple_intropattern(x) :=
  let H := fresh "H" x "_lookup" in
  let i := lazymatch type of i with
           | nat => i
           | Z => constr:(Z.to_nat i)
           | u64 => constr:(int.nat i)
           end in
  destruct (list_lookup_lt _ l i) as [x H];
  [ try solve [ len ]
  | ].

Theorem wp_Dec__GetInts stk E dec_v (xs: list u64) r (n: u64) s q data :
  length xs = int.nat n →
  {{{ is_dec dec_v ((EncUInt64 <$> xs) ++ r) s q data }}}
    Dec__GetInts dec_v #n @ stk; E
  {{{ (s':Slice.t), RET slice_val s'; is_dec dec_v r s q data ∗ is_slice s' uint64T 1 xs }}}.
Proof.
  iIntros (Hlen Φ) "Hdec HΦ".
  wp_rec; wp_pures.
  wp_apply (typed_mem.wp_AllocAt (slice.T uint64T)).
  { apply zero_val_ty', has_zero_slice_T. }
  iIntros (s_l) "Hsptr".
  wp_pures.
  wp_apply wp_ref_to; auto.
  iIntros (i_l) "Hi".
  wp_pures.
  wp_apply (wp_forUpto (λ i,
                        let done := take (int.nat i) xs in
                        let todo := drop (int.nat i) xs in
                        "Hdec" ∷ is_dec dec_v ((EncUInt64 <$> todo) ++ r) s q data ∗
                        "*" ∷ ∃ s, "Hsptr" ∷ s_l ↦[slice.T uint64T] (slice_val s) ∗
                                   "Hdone" ∷ is_slice s uint64T 1 done
           )%I with "[] [$Hi Hsptr Hdec]").
  - word.
  - clear Φ.
    iIntros (?) "!>".
    iIntros (Φ) "(HI&Hi&%Hlt) HΦ"; iNamed "HI".
    wp_pures.
    list_elem xs i as x.
    rewrite (drop_S _ _ _ Hx_lookup) /=.
    wp_apply (wp_Dec__GetInt with "Hdec"); iIntros "Hdec".
    wp_load.
    wp_apply (wp_SliceAppend with "Hdone"); iIntros (s') "Hdone".
    wp_store.
    iApply "HΦ"; iFrame.
    replace (int.nat (word.add i 1)) with (S (int.nat i)) by word.
    iFrame "Hdec".
    iExists _; iFrame.
    erewrite take_S_r; eauto.
  - rewrite drop_0; iFrame "Hdec".
    iExists Slice.nil.
    iFrame.
    rewrite take_0.
    iApply is_slice_nil; auto.
  - iIntros "(HI&Hi)"; iNamed "HI".
    wp_load.
    iApply "HΦ"; iFrame.
    rewrite -> take_ge, drop_ge by len.
    by iFrame.
Qed.

(* special case where GetInts is the last thing and there are no more remaining
items to decode *)
Theorem wp_Dec__GetInts_complete stk E dec_v (xs: list u64) (n: u64) s q data :
  length xs = int.nat n →
  {{{ is_dec dec_v (EncUInt64 <$> xs) s q data }}}
    Dec__GetInts dec_v #n @ stk; E
  {{{ (s':Slice.t), RET slice_val s'; is_dec dec_v [] s q data ∗ is_slice s' uint64T 1 xs }}}.
Proof.
  iIntros (? Φ) "Hpre HΦ".
  wp_apply (wp_Dec__GetInts _ _ _ _ [] with "[Hpre]"); first by eauto.
  - rewrite app_nil_r //.
  - auto.
Qed.

End goose_lang.

Typeclasses Opaque has_encoding.
