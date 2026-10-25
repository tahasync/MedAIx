"""Patient profile validation and serialization.

Implements the Sprint 3 account-creation questionnaire (``docs/questionnaire.md``)
on the wire shape agreed in the sprint contract:

- every ``PUT /profile`` field is optional and only the keys present change;
- onboarding is complete when name, date of birth, sex at birth and both
  consent switches are stored. Weight, height and conditions are optional;
- health answers that do not apply to the user's group (pregnancy for anyone
  who is not female, prostate for anyone who is not a man of 40+) are dropped
  silently, never stored and never an error;
- consent is only ever *given* here. Withdrawing it means deleting the health
  data (``DELETE /profile``).

Legacy Sprint 2 keys (``age``, ``weight``, ``height``, ``sex``) are still
accepted so older clients keep working.
"""

from datetime import date, datetime

from pydantic import (
    BaseModel,
    Field,
    ValidationError,
    field_validator,
    model_validator,
)

from models import User, utc_now

CONSENT_VERSION = "2026-10"
ADULT_AGE = 18
EARLIEST_BIRTH_YEAR = 1900
PROSTATE_MIN_AGE = 40

SEX_AT_BIRTH_OPTIONS = ("female", "male", "prefer_not_to_say")
PREGNANCY_OPTIONS = ("no", "pregnant", "breastfeeding", "prefer_not_to_say")
PROSTATE_OPTIONS = ("no", "yes", "prefer_not_to_say")
FIRST_GOAL_OPTIONS = ("reports", "medicines", "condition", "habits")
# Older clients sent ``sex: "other"``; the questionnaire has no such answer.
_LEGACY_SEX = {"other": "prefer_not_to_say"}

NAME_MESSAGE = "Use a name between 2 and 60 characters."
UNDER_AGE_MESSAGE = "MedAIx is for adults. A parent or guardian can use it for you."
FUTURE_DOB_MESSAGE = "Enter a date of birth in the past."
EARLY_DOB_MESSAGE = "Enter a date of birth after 1900."
DOB_FORMAT_MESSAGE = "Enter your date of birth as a date (YYYY-MM-DD)."
SEX_MESSAGE = "Choose female, male, or prefer not to say."
PREGNANCY_MESSAGE = "Choose no, pregnant, breastfeeding, or prefer not to say."
PROSTATE_MESSAGE = "Choose no, yes, or prefer not to say."
FIRST_GOAL_MESSAGE = "Choose reports, medicines, condition, or habits."
HEIGHT_MESSAGE = "Enter a height in centimetres, from 50 to 250."
WEIGHT_MESSAGE = "Enter a weight in kilograms, from 2 to 400."
LEGACY_AGE_MESSAGE = "Enter an age from 1 to 120."
CONSENT_WITHDRAWAL_MESSAGE = (
    "Consent can only be withdrawn by deleting your health data."
)
CONSENT_SHAPE_MESSAGE = "Send consent as the terms and health_data switches."
TAKES_MEDICINES_MESSAGE = "Answer yes or no to whether you take regular medicines."
GENERIC_MESSAGE = "Check the profile details and try again."


def today() -> date:
    """Today's date in UTC. A function so tests can pin the clock."""
    return utc_now().date()


def age_on(born: date, on: date) -> int:
    """Completed years between ``born`` and ``on``."""
    years = on.year - born.year
    if (on.month, on.day) < (born.month, born.day):
        years -= 1
    return years


def _normalise_enum(value: str) -> str:
    """``"Prefer not to say"`` → ``"prefer_not_to_say"``; lowercase otherwise."""
    return "_".join(value.strip().lower().replace("-", " ").split())


def _enum(value: str | None, options: tuple[str, ...], message: str) -> str | None:
    if value is None:
        return None
    cleaned = _normalise_enum(value)
    if cleaned not in options:
        raise ValueError(message)
    return cleaned


def normalise_sex(value: str | None) -> str | None:
    """Canonical ``sex_at_birth`` for a stored or submitted value, or None."""
    if value is None:
        return None
    cleaned = _normalise_enum(value)
    cleaned = _LEGACY_SEX.get(cleaned, cleaned)
    return cleaned if cleaned in SEX_AT_BIRTH_OPTIONS else None


class ConsentUpdate(BaseModel):
    terms: bool | None = None
    health_data: bool | None = None

    @model_validator(mode="after")
    def cannot_withdraw(self) -> "ConsentUpdate":
        if self.terms is False or self.health_data is False:
            raise ValueError(CONSENT_WITHDRAWAL_MESSAGE)
        return self


class ProfileUpdate(BaseModel):
    """Partial update: only the fields the client sent are applied."""

    name: str | None = None
    date_of_birth: date | None = None
    sex_at_birth: str | None = None
    consent: ConsentUpdate | None = None
    conditions: str | None = Field(default=None, max_length=2000)
    allergies: str | None = Field(default=None, max_length=2000)
    takes_medicines: bool | None = None
    medications: str | None = Field(default=None, max_length=2000)
    pregnancy_status: str | None = None
    prostate_urinary_issue: str | None = None
    first_goal: str | None = None
    height_cm: float | None = Field(default=None, ge=50, le=250)
    weight_kg: float | None = Field(default=None, ge=2, le=400)
    # Legacy aliases kept for older clients.
    age: int | None = Field(default=None, ge=1, le=120)
    weight: float | None = Field(default=None, ge=2, le=400)
    height: float | None = Field(default=None, ge=50, le=250)
    sex: str | None = None

    @field_validator("name")
    @classmethod
    def name_length(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = " ".join(value.split())
        if not 2 <= len(cleaned) <= 60:
            raise ValueError(NAME_MESSAGE)
        return cleaned

    @field_validator("date_of_birth")
    @classmethod
    def adult_and_plausible(cls, value: date | None) -> date | None:
        if value is None:
            return None
        now = today()
        if value > now:
            raise ValueError(FUTURE_DOB_MESSAGE)
        if value.year < EARLIEST_BIRTH_YEAR:
            raise ValueError(EARLY_DOB_MESSAGE)
        if age_on(value, now) < ADULT_AGE:
            raise ValueError(UNDER_AGE_MESSAGE)
        return value

    @field_validator("sex_at_birth", "sex")
    @classmethod
    def known_sex(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = normalise_sex(value)
        if cleaned is None:
            raise ValueError(SEX_MESSAGE)
        return cleaned

    @field_validator("conditions", "medications", "allergies")
    @classmethod
    def trim_text(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None

    @field_validator("pregnancy_status")
    @classmethod
    def known_pregnancy_status(cls, value: str | None) -> str | None:
        return _enum(value, PREGNANCY_OPTIONS, PREGNANCY_MESSAGE)

    @field_validator("prostate_urinary_issue")
    @classmethod
    def known_prostate_answer(cls, value: str | None) -> str | None:
        return _enum(value, PROSTATE_OPTIONS, PROSTATE_MESSAGE)

    @field_validator("first_goal")
    @classmethod
    def known_goal(cls, value: str | None) -> str | None:
        return _enum(value, FIRST_GOAL_OPTIONS, FIRST_GOAL_MESSAGE)


_FIELD_MESSAGES = {
    "name": NAME_MESSAGE,
    "date_of_birth": DOB_FORMAT_MESSAGE,
    "sex_at_birth": SEX_MESSAGE,
    "sex": SEX_MESSAGE,
    "consent": CONSENT_SHAPE_MESSAGE,
    "terms": CONSENT_SHAPE_MESSAGE,
    "health_data": CONSENT_SHAPE_MESSAGE,
    "conditions": "Shorten the conditions text and try again.",
    "allergies": "Shorten the allergies text and try again.",
    "medications": "Shorten the medications text and try again.",
    "takes_medicines": TAKES_MEDICINES_MESSAGE,
    "pregnancy_status": PREGNANCY_MESSAGE,
    "prostate_urinary_issue": PROSTATE_MESSAGE,
    "first_goal": FIRST_GOAL_MESSAGE,
    "height_cm": HEIGHT_MESSAGE,
    "height": HEIGHT_MESSAGE,
    "weight_kg": WEIGHT_MESSAGE,
    "weight": WEIGHT_MESSAGE,
    "age": LEGACY_AGE_MESSAGE,
}


def profile_error_message(exc: ValidationError) -> str:
    """First validation problem, in wording a patient can act on.

    Validator messages (``ValueError`` raised above) are shown verbatim; type
    and range errors from pydantic itself are mapped per field so a raw
    "Input should be greater than or equal to 50" never reaches the app.
    """
    errors = exc.errors()
    if not errors:
        return GENERIC_MESSAGE
    first = errors[0]
    raised = (first.get("ctx") or {}).get("error")
    if first.get("type") == "value_error" and raised is not None:
        return str(raised)
    loc = first.get("loc") or ("profile",)
    return _FIELD_MESSAGES.get(str(loc[-1]), GENERIC_MESSAGE)


def sex_at_birth_of(user: User) -> str | None:
    """Stored sex at birth, falling back to the legacy ``sex`` column."""
    return normalise_sex(user.sex_at_birth) or normalise_sex(user.sex)


def derived_age(user: User, on: date | None = None) -> int | None:
    """Age from ``date_of_birth`` when stored, else the legacy ``age`` value."""
    if user.date_of_birth is not None:
        return age_on(user.date_of_birth, on or today())
    return user.age


def consent_given(user: User) -> bool:
    return bool(user.consent_terms) and bool(user.consent_health_data)


def apply_profile_update(
    user: User,
    update: ProfileUpdate,
    *,
    now: datetime | None = None,
) -> None:
    """Write the submitted fields onto ``user``; untouched fields keep their value.

    ``now`` pins the consent timestamp in tests.
    """
    sent = update.model_fields_set

    if "name" in sent:
        user.name = update.name
    if "date_of_birth" in sent:
        user.date_of_birth = update.date_of_birth
    if "age" in sent:
        user.age = update.age

    if "sex_at_birth" in sent:
        user.sex_at_birth = user.sex = update.sex_at_birth
    elif "sex" in sent:
        user.sex_at_birth = user.sex = update.sex

    if "height_cm" in sent:
        user.height = update.height_cm
    elif "height" in sent:
        user.height = update.height
    if "weight_kg" in sent:
        user.weight = update.weight_kg
    elif "weight" in sent:
        user.weight = update.weight

    for field in ("conditions", "medications", "allergies", "takes_medicines", "first_goal"):
        if field in sent:
            setattr(user, field, getattr(update, field))

    if update.consent is not None:
        stamped = False
        if update.consent.terms:
            user.consent_terms = True
            stamped = True
        if update.consent.health_data:
            user.consent_health_data = True
            stamped = True
        if stamped:
            user.consent_version = CONSENT_VERSION
            user.consent_accepted_at = now or utc_now()

    # Group-specific answers: kept only while the user is in that group.
    sex = sex_at_birth_of(user)
    if sex == "female":
        if "pregnancy_status" in sent:
            user.pregnancy_status = update.pregnancy_status
    else:
        user.pregnancy_status = None

    age = derived_age(user)
    if sex == "male" and age is not None and age >= PROSTATE_MIN_AGE:
        if "prostate_urinary_issue" in sent:
            user.prostate_urinary_issue = update.prostate_urinary_issue
    else:
        user.prostate_urinary_issue = None


def clear_health_data(user: User) -> None:
    """Forget every health answer and the consent that allowed storing them.

    Name, email and the sign-in id stay so the account itself survives.
    """
    for field in (
        "age",
        "weight",
        "height",
        "sex",
        "conditions",
        "medications",
        "allergies",
        "date_of_birth",
        "sex_at_birth",
        "consent_terms",
        "consent_health_data",
        "consent_version",
        "consent_accepted_at",
        "takes_medicines",
        "pregnancy_status",
        "prostate_urinary_issue",
        "first_goal",
    ):
        setattr(user, field, None)


def onboarding_complete(user: User) -> bool:
    return (
        bool(user.name)
        and user.date_of_birth is not None
        and sex_at_birth_of(user) is not None
        and consent_given(user)
    )


def consent_payload(user: User) -> dict[str, object] | None:
    if not consent_given(user):
        return None
    accepted_at = user.consent_accepted_at
    return {
        "terms": True,
        "health_data": True,
        "version": user.consent_version,
        "accepted_at": accepted_at.isoformat() if accepted_at else None,
    }


def profile_payload(user: User) -> dict[str, object]:
    sex = sex_at_birth_of(user)
    dob = user.date_of_birth
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "date_of_birth": dob.isoformat() if dob else None,
        "age": derived_age(user),
        "sex_at_birth": sex,
        "consent": consent_payload(user),
        "conditions": user.conditions or "",
        "allergies": user.allergies or "",
        "takes_medicines": user.takes_medicines,
        "medications": user.medications or "",
        "pregnancy_status": user.pregnancy_status,
        "prostate_urinary_issue": user.prostate_urinary_issue,
        "first_goal": user.first_goal,
        "height_cm": user.height,
        "weight_kg": user.weight,
        # Legacy aliases, kept for old clients.
        "weight": user.weight,
        "height": user.height,
        "sex": sex,
        "onboarding_complete": onboarding_complete(user),
    }
