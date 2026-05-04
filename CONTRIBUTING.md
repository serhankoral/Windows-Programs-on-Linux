# Contributing / Katkı Rehberi

**[English](#english)** | [Türkçe](#türkçe)

---

## English

Thank you for considering contributing to this project!

### How to Contribute

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/my-feature`
3. **Test** your changes on a fresh Ubuntu installation
4. **Commit** with a clear message: `git commit -m "feat: add my feature"`
5. **Push** to your fork: `git push origin feature/my-feature`
6. **Open** a Pull Request

### Commit Message Format

```
type: short description

Types:
  feat     — new feature
  fix      — bug fix
  docs     — documentation change
  refactor — code refactor (no feature change)
  test     — adding tests
  chore    — maintenance
```

### Testing

Before submitting a PR, please test on:
- [ ] Fresh Ubuntu 24.04 installation
- [ ] Script runs without errors from start to finish
- [ ] Both Turkish and English language modes
- [ ] Install mode works
- [ ] Uninstall mode cleans everything

### Reporting Bugs

Use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) template.

Include:
- Ubuntu version (`lsb_release -a`)
- Error message (full output)
- Steps to reproduce

---

## Türkçe

Bu projeye katkıda bulunmayı düşündüğünüz için teşekkürler!

### Nasıl Katkıda Bulunurum?

1. Repoyu **fork**'layın
2. Özellik dalı **oluşturun**: `git checkout -b ozellik/yeni-ozellik`
3. Değişikliklerinizi temiz Ubuntu kurulumunda **test edin**
4. Net mesajla **commit**'leyin: `git commit -m "feat: yeni özellik ekle"`
5. Fork'unuza **push**'layın: `git push origin ozellik/yeni-ozellik`
6. Pull Request **açın**

### Hata Bildirme

[Hata Bildirimi](.github/ISSUE_TEMPLATE/bug_report.md) şablonunu kullanın.

Şunları ekleyin:
- Ubuntu sürümü (`lsb_release -a`)
- Hata mesajı (tam çıktı)
- Hatayı tekrarlama adımları
