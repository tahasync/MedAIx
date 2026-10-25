"""SQLAlchemy models for MedAIx.

Structured rows only — report images and medicine photos belong in Supabase
Storage, not Postgres (Neon's free tier is 0.5 GB).
"""

from datetime import UTC, datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
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
    age = Column(Integer, nullable=True)
    weight = Column(Float, nullable=True)
    height = Column(Float, nullable=True)
    sex = Column(String, nullable=True)
    conditions = Column(Text, nullable=True)
    medications = Column(Text, nullable=True)
    allergies = Column(Text, nullable=True)
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
    logged_at = Column(DateTime, default=utc_now)

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