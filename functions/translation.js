const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");

exports.translateAudio = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
  
  const {audioUrl, srcLang, tgtLang} = data;
  
  const response = await axios.post("http://YOUR_VPS_IP:5000/translate", {
    audioUrl,
    srcLang: srcLang || "eng_Latn",
    tgtLang: tgtLang || "spa_Latn"
  });
  
  return {translatedAudioUrl: response.data.audioUrl, text: response.data.text};
});
