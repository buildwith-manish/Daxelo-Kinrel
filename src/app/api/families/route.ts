import { NextResponse } from "next/server";
import { getFamilies, getFamilyById, getFamilyMembers } from "@/lib/store";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const familyId = searchParams.get("id");

    if (familyId) {
      const family = getFamilyById(familyId);
      if (!family) {
        return NextResponse.json(
          { error: "Family not found" },
          { status: 404 }
        );
      }
      const members = getFamilyMembers(familyId);
      return NextResponse.json({ family, members });
    }

    const families = getFamilies();
    return NextResponse.json({ families });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to fetch families" },
      { status: 500 }
    );
  }
}
