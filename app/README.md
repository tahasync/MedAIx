# MedAIx

AI-powered clinical decision-support app (Final Year Project). Upload a lab report → OCR + NLP simplify it into plain language → track it against a patient profile → flag risk trends → check drug interactions → scan medicine packaging → recommend a specialist → share a curated view with a doctor via time-limited QR → wellness logging + reminders.

## Repo structure (monorepo)

```
medaix/
├── app/    # Flutter client (this folder)
├── api/    # FastAPI backend (OCR, NLP, risk rules, drug checks)
└── .github/workflows/   # CI/CD (added in Week 0 setup)
```

## Product requirements

The PRD / 32-week execution plan lives outside the repo at `D:\Fyp\MedAIx_32Week_Solo_Plan-1.md` (kept out of version control by owner's choice). The roadmap snapshot below mirrors it:

- **Semester 1 (Sprints 1–8):** Upload + OCR → NLP simplification + profile → risk/trend analysis → wellness tracking → integration → advisor feedback → buffer → Sem-1 defense.
- **Semester 2 (Sprints 9–16):** Drug safety checker → medicine scanner → doctor recommendation → QR sharing → doctor portal + notifications → security/perf testing → user testing + deployment → final docs.

## Stack

Flutter + Riverpod · Material 3 Expressive "liquid glass" · FastAPI · SQLite → Postgres · Tesseract OCR · spaCy · Firebase Auth/FCM · Railway.

## Getting started

```bash
flutter pub get
flutter run
```
