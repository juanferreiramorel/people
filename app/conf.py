from pydantic import BaseSettings


class Settings(BaseSettings):
    PEOPLE_DB_URL: str = None
    RUC_DB_URL: str = None
    JWT_SECRET: str = None
    JWT_ALGORITHM: str = "HS256"
    ENABLE_DOCS: bool = False

    class Config:
        env_file = ".env"

settings = Settings()
