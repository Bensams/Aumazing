// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GenerateImageRequest {
  prompt: string;
  aspect_ratio?: "1:1" | "3:2" | "2:3" | "16:9" | "9:16";
  resolution?: "1K" | "2K" | "4K";
  background?: "transparent" | "white" | "black";
  callBackUrl?: string;
}

interface KieJobResponse {
  code: number;
  msg: string;
  data: {
    jobId: string;
  };
}

interface KieJobStatusResponse {
  code: number;
  msg: string;
  data: {
    status: "PENDING" | "PROCESSING" | "SUCCESS" | "FAILED";
    result?: {
      images: Array<{
        url: string;
      }>;
    };
    failReason?: string;
  };
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify the request is authenticated
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      throw new Error("Missing authorization header");
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    );

    const {
      data: { user },
    } = await supabaseClient.auth.getUser();

    if (!user) {
      throw new Error("Unauthorized");
    }

    const body: GenerateImageRequest = await req.json();

    if (!body.prompt) {
      throw new Error("prompt is required");
    }

    // Get kie.ai API key from environment (set this in Supabase dashboard)
    const kieApiKey = Deno.env.get("KIE_API_KEY");
    if (!kieApiKey) {
      throw new Error("KIE_API_KEY not configured");
    }

    // Create the image generation job
    const createJobResponse = await fetch(
      "https://api.kie.ai/api/v1/jobs/createTask",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${kieApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-image-2-5-flare-text-to-image",
          callBackUrl: body.callBackUrl,
          input: {
            prompt: body.prompt,
            aspect_ratio: body.aspect_ratio || "3:2",
            resolution: body.resolution || "1K",
            background: body.background || "transparent",
          },
        }),
      }
    );

    if (!createJobResponse.ok) {
      const errorText = await createJobResponse.text();
      throw new Error(
        `kie.ai API error: ${createJobResponse.status} - ${errorText}`
      );
    }

    const jobResult: KieJobResponse = await createJobResponse.json();

    if (jobResult.code !== 200) {
      throw new Error(`kie.ai job creation failed: ${jobResult.msg}`);
    }

    const jobId = jobResult.data.jobId;

    // Poll for job completion (max 60 seconds)
    const maxAttempts = 30;
    const pollInterval = 2000; // 2 seconds

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      await new Promise((resolve) => setTimeout(resolve, pollInterval));

      const statusResponse = await fetch(
        `https://api.kie.ai/api/v1/jobs/queryTask?jobId=${jobId}`,
        {
          headers: {
            "Authorization": `Bearer ${kieApiKey}`,
          },
        }
      );

      if (!statusResponse.ok) {
        const errorText = await statusResponse.text();
        throw new Error(
          `kie.ai status check failed: ${statusResponse.status} - ${errorText}`
        );
      }

      const statusResult: KieJobStatusResponse = await statusResponse.json();

      if (statusResult.code !== 200) {
        throw new Error(`kie.ai status query failed: ${statusResult.msg}`);
      }

      const status = statusResult.data.status;

      if (status === "SUCCESS" && statusResult.data.result?.images) {
        return new Response(
          JSON.stringify({
            success: true,
            jobId,
            images: statusResult.data.result.images,
          }),
          {
            headers: {
              ...corsHeaders,
              "Content-Type": "application/json",
            },
          }
        );
      } else if (status === "FAILED") {
        throw new Error(
          `Image generation failed: ${statusResult.data.failReason || "Unknown error"}`
        );
      }

      // Still PENDING or PROCESSING, continue polling
    }

    // Timeout reached
    return new Response(
      JSON.stringify({
        success: false,
        error: "Timeout: Image generation took longer than 60 seconds",
        jobId,
        message: "Job is still processing. Check status with jobId.",
      }),
      {
        status: 408,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      }
    );
  } catch (error: any) {
    console.error("generate-image error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        status: 400,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      }
    );
  }
});
