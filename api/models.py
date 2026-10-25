"""SQLAlchemy models for MedAIx.

Structured rows only — report images and medicine photos belong in Supabase
Storage, not Postgres (Neon's free tier is 0.5 GB).
"""

from datetime import UTC, datetime

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    Index,
    String,
    Text,
)
from sqlalchemy.orm import relationship


def utc_now() -> datetime:
    """Current UTC time as a naive datetime.

    The timestamp columns below are ``DateTime`` without a timezone and every
    existing row holds naive UTC, so new values keep that shape. This replaces
    ``datetime.utcnow``, which is deprecated in Python 3.12.
    """
    return datetime.now(UTC).replace(tzinfo=None)

from database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    supabase_uid = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=True)
    email = Column(String, nullable=True)
    # Legacy Sprint 2 columns. ``weight`` is ``weight_kg`` and ``height`` is
    # ``height_cm`` on the wire; ``sex`` mirrors ``sex_at_birth`` for rows
    # written before the Sprint 3 questionnaire. ``age`` is only read when
    # no ``date_of_birth`` is stored.
    age = Column(Integer, nullable=True)
    weight = Column(Float, nullable=True)
    height = Column(Float, nullable=True)
    sex = Column(String, nullable=True)
    conditions = Column(Text, nullable=True)
    medications = Column(Text, nullable=True)
    allergies = Column(Text, nullable=True)
    # Sprint 3 questionnaire (docs/questionnaire.md). New columns are added to
    # existing tables by ``database.add_missing_user_columns`` at startup.
    date_of_birth = Column(Date, nullable=True)
    sex_at_birth = Column(String, nullable=True)
    consent_terms = Column(Boolean, nullable=True)
    consent_health_data = Column(Boolean, nullable=True)
    consent_version = Column(String, nullable=True)
    consent_accepted_at = Column(DateTime, nullable=True)
    takes_medicines = Column(Boolean, nullable=True)
    pregnancy_status = Column(String, nullable=True)
    prostate_urinary_issue = Column(String, nullable=True)
    first_goal = Column(String, nullable=True)
    created_at = Column(DateTime, default=utc_now)

    reports = relationship("Report", back_populates="user")
    medicines = relationship("Medicine", back_populates="user")
    wellness_logs = relationship("WellnessLog", back_populates="user")
    qr_sessions = relationship("QRSession", back_populates="user")


class Report(Base):
    __tablename__ = "reports"

    id = Column(Integer, primary_key=True, index=True)
    # Nullable so rows uploaded before sign-in still load. New uploads set this
    # from the verified Supabase user. A missing owner is treated as not found.
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    image_path = Column(String, nullable=True)
    original_text = Column(Text, nullable=True)
    simplified_text = Column(Text, nullable=True)
    ocr_confidence = Column(Float, nullable=True)
    # List title: user override, else derived from the detected panel (never
    # the first OCR line — that is usually a letterhead or a patient name).
    title = Column(String, nullable=True)
    derived_title = Column(String, nullable=True)
    report_date = Column(Date, nullable=True)
    attention_count = Column(Integer, nullable=True)
    values_read = Column(Integer, nullable=True)
    values_expected = Column(Integer, nullable=True)
    parse_note = Column(String, nullable=True)
    uploaded_at = Column(DateTime, default=utc_now)
    processed_at = Column(DateTime, default=utc_now)

    user = relationship("User", back_populates="reports")


class Medicine(Base):
    __tablename__ = "medicines"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)
    image_path = Column(String, nullable=True)
    prescribed = Column(Boolean, default=False)
    interactions_checked = Column(Boolean, default=False)

    user = relationship("User", back_populates="medicines")


class WellnessLog(Base):
    __tablename__ = "wellness_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    log_type = Column(String, nullable=False)
    value = Column(Float, nullable=False)
    target = Column(Float, nullable=True)
    label = Column(String, nullable=True)
    # Client-generated id makes offline replay safe after an ambiguous timeout.
    client_id = Column(String, nullable=True)
    logged_at = Column(DateTime, default=utc_now)

    __table_args__ = (
        Index("uq_wellness_logs_user_client_id", "user_id", "client_id", unique=True),
        Index("ix_wellness_logs_user_logged_at", "user_id", "logged_at"),
    )

    user = relationship("User", back_populates="wellness_logs")


class QRSession(Base):
    __tablename__ = "qr_sessions"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String, nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=utc_now)
    expires_at = Column(DateTime, nullable=False)
    revoked = Column(Boolean, default=False)

    user = relationship("User", back_populates="qr_sessions")
