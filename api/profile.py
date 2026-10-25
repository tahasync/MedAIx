"""Patient profile validation and serialization.

Onboarding is complete when age, weight, height, and sex are stored. Conditions,
medications, and allergies may be blank. That blank is a real answer ("none"),
not a missing step.
"""

from pydantic import BaseModel, Field, ValidationError, field_validator

from models import User

_SEX_OPTIONS = {"female": "female", "male": "male", "other": "other"}


class ProfileUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=80)
    age: int = Field(ge=1, le=120)
    weight: float = Field(gt=0, le=500)
    height: float = Field(gt=30, le=250)
    sex: str
    conditions: str = Field(default="", max_length=2000)
    medications: str = Field(default="", max_length=2000)
    allergies: str = Field(default="", max_length=2000)

    @field_validator("name")
    @classmethod
    def blank_name_is_absent(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None

    @field_validator("conditions", "medications", "allergies")
    @classmethod
    def trim_text(cls, value: str) -> str:
        return value.strip()

    @field_validator("sex")
    @classmethod
    def known_sex(cls, value: str) -> str:
        cleaned = value.strip().lower()
        if cleaned not in _SEX_OPTIONS:
            raise ValueError("Choose female, male, or other.")
        return cleaned


def profile_error_message(exc: ValidationError) -> str:
    """First validation problem, in wording a patient can act on."""
    errors = exc.errors()
    if not errors:
        return "Check the profile details and try again."
    field = str(errors[0].get("loc", ("profile",))[-1])
    return {
        "name": "Use a name of 80 characters or fewer.",
        "age": "Enter an age from 1 to 120.",
        "weight": "Enter a weight in kilograms, up to 500.",
        "height": "Enter a height in centimetres, from 31 to 250.",
        "sex": "Choose female, male, or other.",
        "conditions": "Shorten the conditions text and try again.",
        "medications": "Shorten the medications text and try again.",
        "allergies": "Shorten the allergies text and try again.",
    }.get(field, "Check the profile details and try again.")


def onboarding_complete(user: User) -> bool:
    return (
        user.age is not None
        and user.weight is not None
        and user.height is not None
        and bool(user.sex)
    )


def profile_payload(user: User) -> dict[str, object]:
    return {
        "id": user.id,
        "name": user.name,
        "age": user.age,
        "weight": user.weight,
        "height": user.height,
        "sex": user.sex,
        "conditions": user.conditions or "",
        "medications": user.medications or "",
        "allergies": user.allergies or "",
        "onboarding_complete": onboarding_complete(user),
    }
