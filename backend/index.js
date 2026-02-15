const express = require('express');
const axios = require('axios');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const { CUELINKS_API_KEY, CUELINKS_USER_ID } = process.env;

app.post("/convert-link", async (req, res) => {
  const { original_url } = req.body;
  if (!original_url) {
    return res.status(400).json({ success: false, message: "Missing URL" });
  }
  console.log("Converting URL:", original_url);

  try {
    const response = await axios.get('https://www.cuelinks.com/api/v2/links.json', {
      params: {
        url : original_url,
        shorten : true,
      },
      headers: {
        'Authorization': `Token ${process.env.CUELINKS_API_KEY}`
      }
    });
    console.log("Cuelinks response:", response.data);
    res.json({ success: true, data: response.data });
  } catch (err) {
    console.error("Cuelinks error:", err.response?.data || err.message);
    res.status(500).json({ success: false, message: "Conversion failed" });
  }
});

app.listen(process.env.PORT, () =>
  console.log(`✅ Backend running on http://localhost:${process.env.PORT}`)
);
