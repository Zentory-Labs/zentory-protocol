import { updateSession } from "@/utils/supabase/middleware";

export async function middleware(request: Request) {
  return await updateSession(request as never);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
