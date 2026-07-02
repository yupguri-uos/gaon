from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import urlencode

import httpx

from app.config import settings

KAKAO_AUTH_URL = "https://kauth.kakao.com/oauth/authorize"
KAKAO_TOKEN_URL = "https://kauth.kakao.com/oauth/token"
KAKAO_USER_INFO_URL = "https://kapi.kakao.com/v2/user/me"

class KakaoAPIError(Exception):
    """카카오 인증 API 호출 실패."""
    
    
@dataclass(frozen = True)
class KakaoUserInfo:
    kakao_id: str
    nickname : str | None

def get_kakao_login_url(state: str) -> str:
    params = {
        "client_id": settings.kakao_rest_api_key,
        "redirect_uri": settings.kakao_redirect_uri,
        "response_type":"code",
        "state": state,
    }
    
    return f"{KAKAO_AUTH_URL}?{urlencode(params)}"



async def exchange_code_for_access_token(code:str) -> str:
    """
    인가 코드(code)를 카카오 access_token으로 교환
    """
    
    data = {
        "grant_type" : "authorizatoin_code", 
        "client_id": settings.kakao_rest_api_key,
        "redirect_uri": settings.kakao_redirect_uri,
        "code":code,
    }
    
    headers = {
        "Content-Type": "application/x-www-form-urlencoded;charset=utf-8"
    }
    
    if settings.kakao_client_secret: 
        data["client_secret"] = settings.kakao_client_secret
    
    try: 
        async with httpx.AsyncClient(timeout = 10.0) as client: 
            response = await client.post(
                KAKAO_TOKEN_URL, 
                data = data, 
                headers = headers
            )
            response.raise_for_status()
            return response.json()["access_token"]
        
    except (httpx.HTTPError, KeyError, ValueError) as exc:
        raise KakaoAPIError("카카오 토큰 발급에 실패했습니다") from exc
    


async def fetch_kakao_user(access_token: str) -> KakaoUserInfo:
    """
     액세스 토큰으로 카카오 사용자 정보를 가져오는 역할 
    """
    try: 
        async with httpx.AsyncClient(timeout = 10.0) as client:
            response = await client.get(
                KAKAO_USER_INFO_URL, 
                headers = {
                    "Authorization": f"Bearer {access_token}",
                },
            )
            response.raise_for_status()
            data =response.json()
            
        account = data.get("kakao_account") or {}
        profile = account.get("profile") or {}
        
        return KakaoUserInfo(
            kakao_id = str(data["id"]), 
            nickname = profile.get("nickname"),
        )
        
    except (httpx.HTTPError, KeyError, ValueError) as exc: 
        raise KakaoAPIError("카카오 사용자 조회에 실패했습니다") from exc
        
    