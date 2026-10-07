const express = require('express');
const PinataSDK = require('@pinata/sdk');
const cors = require('cors');
const multer = require('multer');
const logger = require('./utils/logger');
require('dotenv').config();

const app = express();
const upload = multer({ storage: multer.memoryStorage() });

// Debug the API key and secret values (sanitized for logging)
const apiKey = process.env.PINATA_API_KEY;
const secretApiKey = process.env.PINATA_API_SECRET;
logger.info(`API Key Status: ${apiKey ? 'Present' : 'Missing'}`);
logger.info(`Secret API Key Status: ${secretApiKey ? 'Present' : 'Missing'}`);

// Initialize Pinata SDK with API key and secret
let pinata;
try {
  if (!apiKey || !secretApiKey) {
    throw new Error('PINATA_API_KEY or PINATA_API_SECRET environment variable is not set or empty');
  }
  pinata = new PinataSDK(apiKey, secretApiKey);
  logger.info('Pinata SDK initialization appears successful');
} catch (error) {
  logger.error('Failed to initialize Pinata SDK:', error.message);
}

app.use(cors({
  origin: ['http://localhost:3000', 'http://192.168.0.236:3000'],
  methods: ['GET', 'POST'],
  allowedHeaders: ['Content-Type']
}));
app.use(express.json());

app.get('/api/test', (req, res) => {
  logger.info('Received test request');
  res.json({ message: 'Server is running' });
});

app.post('/api/upload-to-ipfs', upload.single('file'), async (req, res) => {
  logger.info('Received IPFS upload request', {
    body: req.body,
    file: req.file ? {
      originalname: req.file.originalname,
      mimetype: req.file.mimetype,
      size: req.file.size
    } : null,
    hasFile: !!req.file,
    hasMetadata: !!req.body.pinataMetadata
  });

  try {
    if (!req.file) {
      logger.error('No file provided in request');
      return res.status(400).json({ error: 'No file uploaded' });
    }

    // Parse metadata from request
    let metadata = {};
    if (req.body.pinataMetadata) {
      try {
        metadata = JSON.parse(req.body.pinataMetadata);
        logger.info('Parsed pinataMetadata', { metadata });
      } catch (parseError) {
        logger.error('Failed to parse pinataMetadata', { error: parseError.message });
        return res.status(400).json({ error: 'Invalid pinataMetadata format' });
      }
    }

    const fileName = metadata.name || req.file.originalname || `image_${Date.now()}.${req.file.mimetype.split('/')[1] || 'jpg'}`;
    logger.info('Computed fileName', { fileName });

    // Create a readable stream from buffer
    const readableStreamFromBuffer = new require('stream').Readable();
    readableStreamFromBuffer._read = () => {};
    readableStreamFromBuffer.push(req.file.buffer);
    readableStreamFromBuffer.push(null);

    // Add filename directly to stream object
    readableStreamFromBuffer.path = fileName;

    const options = {
      pinataMetadata: {
        name: fileName,
        keyvalues: metadata.keyvalues || {}
      },
      pinataOptions: {
        cidVersion: 0
      }
    };

    logger.info('Uploading to Pinata with options', { options });
    const result = await pinata.pinFileToIPFS(readableStreamFromBuffer, options);

    const uri = `${process.env.PINATA_GATEWAY}/ipfs/${result.IpfsHash}`;
    logger.info('IPFS upload successful', { uri, hash: result.IpfsHash });
    res.json({ uri });
  } catch (error) {
    logger.error('IPFS upload error', { message: error.message, stack: error.stack });
    res.status(500).json({ error: error.message || 'Failed to upload to IPFS' });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  logger.info(`✅ Pinata Server running on http://localhost:${PORT}`);
});