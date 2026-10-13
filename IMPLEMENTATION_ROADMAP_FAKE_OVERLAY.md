# Roadmap Trien Khai Tool Fake La Bai (Overlay)

Tai lieu nay chot ro huong trien khai theo yeu cau:
- Tool fake.
- Hien thi la bai random dung vi tri dealer.
- Lam theo tung buoc, sai dau fix do.

---

## 1) Muc tieu ky thuat

### Muc tieu chinh
- Overlay co the di chuyen.
- He thong xac dinh duoc vi tri 6 slot bai dealer tren man hinh.
- Hien 6 la random vao dung 6 slot.
- Bubble/frame di dau thi la van nam dung cho (khong troi theo bubble).

### Ngoai pham vi (de tranh lech huong)
- Khong tinh logic baccarat that.
- Khong can du doan ket qua that.

---

## 2) Kien truc can co

### Layer UI
- **Layer A (fixed fullscreen overlay)**: render 6 la theo toa do man hinh.
- **Layer B (bubble/frame draggable)**: dieu khien bat/tat, debug, trigger.

### Data flow
- Native detector -> EventChannel -> Flutter state -> render card slots.

### Model du lieu
- `SlotRectN {left, top, right, bottom}` (toa do chuan hoa 0..1).
- `DetectionFrame {slots[6], confidence, valid, ts}`.
- `OverlayRenderState {inside, cards[6], locked}`.

---

## 3) Chia phase trien khai (chuan de lam/fix)

## Phase 0 - Chot baseline (1 buoi)

### Ban can lam
- Chot 1-2 layout BCR muc tieu (anh/chup man hinh mau).
- Chot kich thuoc may test chinh (ti le man hinh, DPI).

### Minh se code
- Don overlay hien tai ve che do de debug de dang.
- Them log/tracing co ban cho vi tri overlay + state.

### Dieu kien pass
- Build chay on dinh, khong crash khi bat/tat overlay.

---

## Phase 1 - Tach 2 layer overlay (UI dung kien truc)

### Ban can lam
- Xac nhan UX: bubble dung de keo va cau hinh; la bai chi ve tren layer fixed.

### Minh se code
- Layer A fullscreen trong suot de render card.
- Layer B bubble nho de drag.
- Dam bao card render khong phu thuoc toa do bubble.

### Dieu kien pass
- Keo bubble lien tuc nhung card layer khong bi troi theo.

---

## Phase 2 - Slot gia lap (khong detector), de test nhanh

### Ban can lam
- Cung cap 6 slot mock dung layout ban dealer.

### Minh se code
- Ho tro nap `slots[6]` mock.
- Random deck 52 -> lay 6 la khong trung.
- Render card vao dung 6 slot mock.

### Dieu kien pass
- 6 la random hien dung slot mock tren nhieu do phan giai.

---

## Phase 3 - Native detector skeleton + channel contract

### Ban can lam
- Dong y them native service + quyen can thiet tren Android.

### Minh se code
- Tao `MethodChannel` + `EventChannel` contract:
  - `startDetection()`
  - `stopDetection()`
  - stream `DetectionFrame`
- Tao detector stub (tra slot demo theo timer) de test pipeline end-to-end.

### Dieu kien pass
- Flutter nhan frame tu native deu, khong lag/crash.

---

## Phase 4 - Detector that (tim vung dealer + suy ra 6 slot)

### Ban can lam
- Cung cap video/anh mau cac tinh huong:
  - sang/toi
  - zoom khac nhau
  - motion blur nhe

### Minh se code
- Xu ly frame native:
  - tim ROI ban dealer (anchor/canh/vung mau)
  - map ROI -> 6 slot theo ti le layout
- Tra ve `confidence` + `valid`.

### Dieu kien pass
- Slot bat dung vung dealer on dinh >= 90% tren tap test mau.

---

## Phase 5 - Chong rung + lock state (de dung duoc thuc te)

### Ban can lam
- Xac nhan nguong UX (do tre chap nhan duoc).

### Minh se code
- Smoothing (EMA/Kalman nhe) cho rect.
- `lockInMs` / `lockOutMs`.
- Hysteresis threshold (vao vung 0.14, ra vung 0.10).

### Dieu kien pass
- Khong nhay la khi camera/man hinh dao nhe.

---

## Phase 6 - Hoan thien profile theo sanh/layout

### Ban can lam
- Liet ke profile can ho tro (Sanh A, B, C...).

### Minh se code
- Luu profile detector:
  - nguong mau/anchor
  - offset slot
  - tham so smoothing
- Cho chon profile trong app debug.

### Dieu kien pass
- Chuyen profile khong can build lai app.

---

## 4) Viec cua ban vs viec cua minh (tong hop nhanh)

### Ban can lam
- Chot layout muc tieu + bo du lieu test (anh/video).
- Test tren may that va bao bug theo checklist.
- Xac nhan UX va nguong (do tre, do nhay, vi tri).

### Minh se code
- Toan bo luong Flutter overlay + state + render.
- Native channel + detector pipeline + smoothing.
- Cong cu debug de fix nhanh tung phase.

---

## 5) Checklist test moi phase (copy dung lien)

- [ ] Bat/tat overlay on dinh
- [ ] Keo bubble khong lam troi vi tri card fixed
- [ ] Render du 6 la, khong trung trong 1 lan random
- [ ] Khi detector invalid -> an/face-down dung logic
- [ ] FPS/pin chap nhan duoc tren may test
- [ ] Khong crash khi doi huong man hinh / app background

---

## 6) Cach lam viec de fix nhanh

- Lam theo phase, khong nhay coc.
- Moi phase chi doi 1-2 bien lon.
- Sau moi phase:
  1) build
  2) test checklist
  3) log bug
  4) fix ngay bug blocker
- Neu phase fail, rollback ve phase truoc da pass.

---

## 7) Thu tu khuyen nghi de bat tay ngay

1. Phase 1 (tach 2 layer)
2. Phase 2 (slot mock)
3. Phase 3 (channel stub)
4. Phase 4 (detector that)
5. Phase 5 (smoothing/lock)
6. Phase 6 (multi profile)

Neu can, tu ngay mai co the bat dau bang **Phase 1 + Phase 2** de co ban demo nhin thay ket qua som nhat.
