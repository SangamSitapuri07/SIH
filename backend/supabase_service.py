import os
import logging
from typing import Dict, Any, Optional, List

logger = logging.getLogger("orca.supabase")

class SupabaseService:
    """
    Supabase Cloud Integration Service for ORCA Box.
    Operates strictly behind an environment-configured boundary.
    If SUPABASE_URL / SUPABASE_ANON_KEY are not present or unreachable,
    all operations gracefully degrade to local storage without blocking safety advisories.
    """

    def __init__(self):
        self.supabase_url = os.getenv("SUPABASE_URL", "").strip()
        self.supabase_anon_key = os.getenv("SUPABASE_ANON_KEY", "").strip()
        self.supabase_service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        self.client = None
        self.is_connected = False

        if self.supabase_url and (self.supabase_anon_key or self.supabase_service_key):
            try:
                from supabase import create_client, Client
                key_to_use = self.supabase_service_key or self.supabase_anon_key
                self.client: Optional[Client] = create_client(self.supabase_url, key_to_use)
                self.is_connected = True
                logger.info(f"Supabase client initialized with endpoint {self.supabase_url}")
            except Exception as e:
                logger.warning(f"Failed to initialize Supabase client: {e}. Fallback to local store.")
                self.is_connected = False
        else:
            logger.info("Supabase credentials not configured in environment. Using local storage fallback.")

    def sync_user_profile(self, user_id: str, profile_data: Dict[str, Any]) -> bool:
        if not self.is_connected or not self.client:
            return False
        try:
            self.client.table("profiles").upsert({
                "user_id": user_id,
                "display_name": profile_data.get("display_name", "Fisherman"),
                "preferred_language": profile_data.get("preferred_language", "en"),
                "preferred_fishing_area": profile_data.get("preferred_fishing_area"),
                "home_harbour": profile_data.get("home_harbour"),
                "vessel_type": profile_data.get("vessel_type"),
                "vessel_registration": profile_data.get("vessel_registration"),
                "notification_preferences": profile_data.get("notification_preferences", {})
            }).execute()
            return True
        except Exception as e:
            logger.error(f"Error syncing profile to Supabase: {e}")
            return False

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        if not self.is_connected or not self.client:
            return None
        try:
            res = self.client.table("profiles").select("*").eq("user_id", user_id).execute()
            if res.data and len(res.data) > 0:
                return res.data[0]
        except Exception as e:
            logger.error(f"Error fetching profile from Supabase: {e}")
        return None
