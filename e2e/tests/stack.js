// Shared helpers: where each service lives, and reading a one-time code out of a service's log.
const { execSync } = require("child_process");
const path = require("path");

const HOST = process.env.STACK_HOST || "localhost";
const BANK = `http://${HOST}:8080`;
const STOREFRONT = `http://${HOST}:8083`;
const PRODUCT = `http://${HOST}:8082`;
const INTERNAL_KEY = process.env.INTERNAL_SERVICE_API_KEY || "change-this-internal-service-key";

// A unique-per-run phone number and Aadhar so reruns against the same database never collide.
function freshIdentity() {
  const n = String(Date.now()).slice(-8);
  return { phone: "9" + n + "0".repeat(1) + String(Math.floor(Math.random() * 10)), aadhar: "5" + n + String(Math.floor(Math.random() * 1000)).padStart(3, "0") };
}

// DEV_LOG_CODES=true makes the services write a code to their log when the email cannot be sent (CI has no mail server).
function codeFromLog(service, kind, phone) {
  const composeDir = path.resolve(__dirname, "..", "..");
  const logs = execSync(`docker compose logs --no-color ${service}`, { cwd: composeDir, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  const matches = [...logs.matchAll(new RegExp(`${kind} code for ${phone} is (\\d{6})`, "g"))];
  return matches.length ? matches[matches.length - 1][1] : null;
}

module.exports = { HOST, BANK, STOREFRONT, PRODUCT, INTERNAL_KEY, freshIdentity, codeFromLog };
