# MedAIx — Account Creation Questionnaire (short version)

Goal: a new user is inside the app in about **90 seconds**. Only questions that the app cannot work safely without are asked at sign-up. Everything else is asked later, at the moment it is useful, so nobody quits at the start.

**Rules**
- 3 screens, 13 questions at most. Only 6 are required.
- Every health question has "Skip" or "Prefer not to say". Skipping never blocks anything.
- One topic per screen, tap-to-answer wherever possible, no typing of long text.
- Camera and notification permissions are not asked here. They are requested the first time a feature needs them.
- Language comes from the phone settings. The user can change it in More.

Legend: **R** = required, **O** = optional, **S** = single select, **M** = multi select.

---

## Screen 1 of 3 — Create your account (required)

| # | Question | Type | Req | Notes |
|---|---|---|---|---|
| 1.1 | What's your name? | Text | R | 2–60 characters |
| 1.2 | What's your email? | Email | R | Verified with a 6-digit code |
| 1.3 | Create a password | Password | R | 8+ characters, one letter and one number, show/hide |
| 1.4 | What's your date of birth? | Date | R | Must be 18 or older. Under 18: "MedAIx is for adults. A parent or guardian can use it for you." Nothing is stored |
| 1.5 | What was your sex at birth? | S | R | Female / Male / Prefer not to say. Needed for correct lab ranges and to show the right questions on the next screen |

**Consent (two switches, not pre-ticked)**

| # | Statement | Req |
|---|---|---|
| 1.6 | I agree to the Terms and Privacy Policy | R |
| 1.7 | I agree MedAIx may process my health data to explain my reports. I understand it gives information and is not a diagnosis | R |

---

## Screen 2 of 3 — Your health basics (all optional, one tap each)

| # | Question | Type | Options | Why |
|---|---|---|---|---|
| 2.1 | Any ongoing conditions? | M chips | Diabetes, Hypertension, Heart disease, Asthma, Thyroid, Kidney disease, None, Prefer not to say | Chooses which values and trends to highlight |
| 2.2 | Any allergies? | M chips | Penicillin, Aspirin or NSAIDs, Peanuts, Dairy, Seafood, None, Prefer not to say | Medicine safety alerts |
| 2.3 | Do you take regular medicines? | S | Yes / No | If Yes: add names by typing or scanning the packet (no doses needed now) |

**One extra question only for the group it applies to (the gender filter)**

| Shown when | # | Question | Options | Why |
|---|---|---|---|---|
| Sex at birth is **Female** (1.5) | 2.4F | Are you pregnant or breastfeeding? | No, Pregnant, Breastfeeding, Prefer not to say | Changes medicine safety and lab ranges |
| Sex at birth is **Male** and age is 40+ | 2.4M | Any prostate or urinary problems? | No, Yes, Prefer not to say | Linked to diabetes and medicine choices |
| Prefer not to say | none | Skip this question | | |

Nobody sees the other group's question. More specific questions for each group (periods, PSA test, hormone therapy and so on) are asked later in **Profile**, never at sign-up.

---

## Screen 3 of 3 — About you (optional, can skip the whole screen)

| # | Question | Type | Options | Why |
|---|---|---|---|---|
| 3.1 | What would you like help with first? | S (pick one) | Understand my lab reports, Check my medicines, Track a condition, Build healthy habits | Sets the first thing the Home screen shows |
| 3.2 | Height and weight | Two numbers | cm / kg with ft / lb toggle | BMI and goals |

Finish with **Create my account**, then **Upload your first report** or **Skip for now**.

---

## Asked later, in context (not at sign-up)

| Question | When it is asked | Where it lives |
|---|---|---|
| Medicine doses and times | When the user adds the first medicine or turns on reminders | Meds |
| Reminder times, notification permission | When the first reminder is turned on | Reminders |
| Blood group, emergency contact | When the user first opens the emergency card or Share with doctor | Share, Profile |
| Family history | When the first trend alert appears ("Does anyone in your family have this?") | Trends |
| Diabetes type | When Diabetes is chosen and the first HbA1c report is uploaded | Report |
| Smoking, alcohol, activity, sleep, diet | When Wellness is first opened, as one tappable card per question | Wellness |
| Pregnancy history, periods, contraception, PCOS, PSA test, hormone therapy | Only if the user opens "Health details" in Profile | Profile |
| Regular doctor, city | On the Find a doctor screen | Doctor match |
| Research data use (optional) | First time the user opens Settings | More |

Rule: ask one question at a time, only when the answer improves what the user is looking at, and never repeat a skipped question more than once.

---

## Data handling

- Name and email are stored apart from health answers. Health answers are encrypted in transit and at rest.
- Consent is saved with a timestamp and policy version.
- Reproductive and hormone answers are kept in a separate group and left out of doctor sharing unless the user ticks them.
- Only stated answers are stored. Nothing is inferred from medicines or symptoms.
- Never ask at sign-up for ID numbers, bank or card details, or religion.
- The user can export or delete all answers in **More > Account**.

## Profile fields produced

`full_name, email, password_hash, date_of_birth, sex_at_birth, consent{terms, health_data, version, accepted_at}, conditions[], allergies[], takes_medicines, medicines[{name}], pregnancy_status (female only), prostate_urinary_issue (male 40+ only), first_goal, height_cm, weight_kg`
