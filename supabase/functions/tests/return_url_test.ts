import { assertEquals } from "jsr:@std/assert@1";
import {
  allowedReturnUrl,
  DEFAULT_RETURN_ORIGINS,
  withOutcome,
} from "../_shared/return_url.ts";

const allowed = ["https://bensams.github.io"];

Deno.test("accepts the web app's own address and drops a stale outcome", () => {
  const url = allowedReturnUrl(
    "https://bensams.github.io/Aumazing-Front-Page/app/?payment=cancelled#/home",
    allowed,
  );
  assertEquals(url?.href, "https://bensams.github.io/Aumazing-Front-Page/app/");
});

Deno.test("adds the outcome to the return address", () => {
  const url = allowedReturnUrl("https://bensams.github.io/Aumazing-Front-Page/app/", allowed)!;
  assertEquals(
    withOutcome(url, "success"),
    "https://bensams.github.io/Aumazing-Front-Page/app/?payment=success",
  );
  assertEquals(
    withOutcome(url, "cancelled"),
    "https://bensams.github.io/Aumazing-Front-Page/app/?payment=cancelled",
  );
});

Deno.test("refuses other sites, plain http and non-URLs", () => {
  for (const raw of [
    "https://evil.example/app/",
    "https://bensams.github.io.evil.example/",
    "http://bensams.github.io/Aumazing-Front-Page/app/",
    "javascript:alert(1)",
    "not a url",
    42,
    null,
  ]) {
    assertEquals(allowedReturnUrl(raw, allowed), null, String(raw));
  }
});

Deno.test("allows local development servers", () => {
  assertEquals(
    allowedReturnUrl("http://localhost:8095/Aumazing-Front-Page/app/", allowed)?.origin,
    "http://localhost:8095",
  );
  assertEquals(allowedReturnUrl("http://127.0.0.1:5000/", allowed)?.origin, "http://127.0.0.1:5000");
});

Deno.test("by default accepts both web app sites and nothing else", () => {
  for (const url of [
    "https://bensams.github.io/Aumazing-Front-Page/app/",
    "https://app.ecnovators.me/app/",
  ]) {
    assertEquals(allowedReturnUrl(url, DEFAULT_RETURN_ORIGINS)?.href, url);
  }
  for (const url of [
    "https://portal.ecnovators.me/",
    "https://app.ecnovators.me.evil.example/app/",
    "http://app.ecnovators.me/app/",
  ]) {
    assertEquals(allowedReturnUrl(url, DEFAULT_RETURN_ORIGINS), null);
  }
});
