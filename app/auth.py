from typing import Optional

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .conf import settings

# Only HMAC-SHA256 is accepted; "none" and asymmetric algorithms are rejected.
ALLOWED_ALGORITHMS = ["HS256"]

_bearer = HTTPBearer(auto_error=False)


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=401, detail=detail, headers={"WWW-Authenticate": "Bearer"}
    )


def jwt_configured() -> bool:
    return bool(settings.JWT_SECRET)


def verificar_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
) -> dict:
    # Fail closed: without a secret no request is ever served.
    if not jwt_configured():
        raise HTTPException(status_code=503, detail="JWT_SECRET no configurado")

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized("Token invalido o ausente")

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.JWT_SECRET,
            algorithms=ALLOWED_ALGORITHMS,
            options={"require": ["exp", "sub"]},
        )
    except jwt.ExpiredSignatureError:
        raise _unauthorized("Token expirado")
    except jwt.InvalidTokenError:
        raise _unauthorized("Token invalido o ausente")

    if not isinstance(payload.get("sub"), str) or not payload["sub"]:
        raise _unauthorized("Token invalido o ausente")
    return payload
