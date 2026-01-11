// lib/javascript/gemini_service.js
const { GoogleGenerativeAI } = require("@google/generative-ai");

// Your API key should be an environment variable.
// This is a common pattern for ExecJS.
function generateSummary(pdfText, apiKey) {
  if (!apiKey) {
    throw new Error("API key is not set.");
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "gemini-1.5-pro-latest" });

  const prompt = `
  You are an expert academic summarizer.
  Summarize the following research paper text into a concise abstract and extract 5-7 key bullet points.
  Format the output as:
  Abstract: [Concise abstract here]
  Key Points:
  - [Key point 1]
  - [Key point 2]
  - ...

  Research Paper Text:
  ${pdfText.substring(0, 15000)} // Limit input to avoid exceeding token limits
  `;

  return model.generateContent(prompt).then((result) => {
    const response = result.response;
    const text = response.text();
    // The rest of the parsing logic will be in Ruby
    return text;
  });
}
// This is important for ExecJS to work. It exposes the function to the Ruby environment.
global.generateSummary = generateSummary;
