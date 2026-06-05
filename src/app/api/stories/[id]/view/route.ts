import { NextResponse } from "next/server";
import { markStoryViewed } from "@/lib/store";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { viewerId } = body;

    if (!viewerId) {
      return NextResponse.json(
        { error: "viewerId is required" },
        { status: 400 }
      );
    }

    const story = markStoryViewed(id, viewerId);
    if (!story) {
      return NextResponse.json(
        { error: "Story not found" },
        { status: 404 }
      );
    }

    return NextResponse.json({ story });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to mark story as viewed" },
      { status: 500 }
    );
  }
}
