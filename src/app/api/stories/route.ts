import { NextResponse } from "next/server";
import { getStoriesGroupedByUser, getStories, addStory } from "@/lib/store";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const familyId = searchParams.get("familyId") || undefined;
    const grouped = searchParams.get("grouped") !== "false";

    if (grouped) {
      const data = getStoriesGroupedByUser(familyId);
      return NextResponse.json({ stories: data });
    }

    const data = getStories(familyId);
    return NextResponse.json({ stories: data });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to fetch stories" },
      { status: 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { userId, familyId, caption, bgGradient } = body;

    if (!userId || !caption) {
      return NextResponse.json(
        { error: "userId and caption are required" },
        { status: 400 }
      );
    }

    const story = addStory({ userId, familyId, caption, bgGradient });
    return NextResponse.json({ story }, { status: 201 });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to create story" },
      { status: 500 }
    );
  }
}
