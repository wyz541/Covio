//! iroh QUIC adapter for the Covio single-file transfer protocol.

use super::{
    ControlEnvelope, ControlMessage, FileChunkFrame, FileStreamHeader, MAX_CONTROL_MESSAGE_BYTES,
    TRANSFER_ALPN, TRANSFER_PROTOCOL_VERSION, TransferError, TransferErrorCode, decode_control,
    decode_hex_32, encode_control, hex_encode, random_hex,
};
use iroh::{
    Endpoint, EndpointAddr, PublicKey, SecretKey,
    endpoint::{Connection, RecvStream, SendStream, presets},
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

const MAX_DATA_RECORD_BYTES: usize = MAX_CONTROL_MESSAGE_BYTES + 1024;

/// One bound iroh endpoint with the Covio transfer ALPN installed.
pub struct IrohTransferEndpoint {
    endpoint: Endpoint,
}

impl IrohTransferEndpoint {
    /// Binds an endpoint with a caller-persisted iroh secret key.
    pub async fn bind(secret_key: SecretKey) -> Result<Self, TransferError> {
        let endpoint = Endpoint::builder(presets::N0)
            .secret_key(secret_key)
            .alpns(vec![TRANSFER_ALPN.to_vec()])
            .bind()
            .await
            .map_err(|_| transport_error("iroh endpoint bind failed"))?;
        Ok(Self { endpoint })
    }

    /// Binds an endpoint with a generated iroh secret key.
    pub async fn bind_generated() -> Result<Self, TransferError> {
        Self::bind(SecretKey::generate()).await
    }

    /// Returns the stable iroh endpoint identifier.
    pub fn endpoint_id(&self) -> String {
        self.endpoint.id().to_string()
    }

    /// Waits until relay and address discovery are ready.
    pub async fn wait_online(&self) {
        self.endpoint.online().await;
    }

    /// Returns the current dialable iroh address.
    pub fn address(&self) -> EndpointAddr {
        self.endpoint.addr()
    }

    /// Connects to one trusted peer and opens the bidirectional control stream.
    pub async fn connect(
        &self,
        address: EndpointAddr,
    ) -> Result<IrohTransferChannel, TransferError> {
        let connection = self
            .endpoint
            .connect(address, TRANSFER_ALPN)
            .await
            .map_err(|_| transport_error("iroh peer connection failed"))?;
        let (control_send, control_recv) = connection
            .open_bi()
            .await
            .map_err(|_| transport_error("iroh control stream open failed"))?;
        Ok(IrohTransferChannel::new(
            connection,
            control_send,
            control_recv,
        ))
    }

    /// Connects only when the address and TLS identity match a paired device key.
    pub async fn connect_trusted(
        &self,
        address: EndpointAddr,
        trusted_public_key_hex: &str,
    ) -> Result<IrohTransferChannel, TransferError> {
        let expected = public_key_from_hex(trusted_public_key_hex)?;
        if address.id != expected {
            return Err(TransferError::new(
                TransferErrorCode::PeerIdentityChanged,
                "iroh address does not match the paired device",
                false,
            ));
        }
        let channel = self.connect(address).await?;
        channel.ensure_trusted_public_key(trusted_public_key_hex)?;
        Ok(channel)
    }

    /// Connects by endpoint id and verifies the paired-device public key.
    ///
    /// The endpoint id is the same Ed25519 key used for pairing. Address
    /// discovery can resolve a relay or direct path for that id.
    pub async fn connect_trusted_public_key(
        &self,
        trusted_public_key_hex: &str,
    ) -> Result<IrohTransferChannel, TransferError> {
        let public_key = public_key_from_hex(trusted_public_key_hex)?;
        self.connect_trusted(EndpointAddr::new(public_key), trusted_public_key_hex)
            .await
    }

    /// Accepts one incoming connection and its bidirectional control stream.
    pub async fn accept_one(&self) -> Result<IrohTransferChannel, TransferError> {
        let incoming = self
            .endpoint
            .accept()
            .await
            .ok_or_else(|| transport_error("iroh endpoint is closed"))?;
        let connection = incoming
            .await
            .map_err(|_| transport_error("iroh incoming connection failed"))?;
        let (control_send, control_recv) = connection
            .accept_bi()
            .await
            .map_err(|_| transport_error("iroh control stream accept failed"))?;
        Ok(IrohTransferChannel::new(
            connection,
            control_send,
            control_recv,
        ))
    }

    /// Waits a bounded time for a new connection.
    ///
    /// A timeout applies only to the idle wait. After an incoming connection
    /// exists, the handshake is not cancelled by the idle interval.
    pub async fn accept_one_with_timeout(
        &self,
        wait: std::time::Duration,
    ) -> Result<Option<IrohTransferChannel>, TransferError> {
        let incoming = match tokio::time::timeout(wait, self.endpoint.accept()).await {
            Ok(Some(incoming)) => incoming,
            Ok(None) => return Ok(None),
            Err(_) => return Ok(None),
        };
        let connection = incoming
            .await
            .map_err(|_| transport_error("iroh incoming connection failed"))?;
        let (control_send, control_recv) = connection
            .accept_bi()
            .await
            .map_err(|_| transport_error("iroh control stream accept failed"))?;
        Ok(Some(IrohTransferChannel::new(
            connection,
            control_send,
            control_recv,
        )))
    }

    /// Closes the iroh endpoint and its accept loop.
    pub async fn close(self) {
        self.endpoint.close().await;
    }
}

/// One iroh connection carrying control records and one unidirectional file stream.
pub struct IrohTransferChannel {
    connection: Connection,
    control_send: SendStream,
    control_recv: RecvStream,
    data_send: Option<SendStream>,
    data_recv: Option<RecvStream>,
    sequence: u64,
    session_nonce: Option<String>,
}

impl IrohTransferChannel {
    fn new(connection: Connection, control_send: SendStream, control_recv: RecvStream) -> Self {
        Self {
            connection,
            control_send,
            control_recv,
            data_send: None,
            data_recv: None,
            sequence: 0,
            session_nonce: None,
        }
    }

    /// Returns the remote iroh endpoint identifier.
    pub fn remote_endpoint_id(&self) -> String {
        self.connection.remote_id().to_string()
    }

    /// Returns the authenticated remote iroh public key as lowercase hex.
    pub fn remote_public_key_hex(&self) -> String {
        hex_encode(self.connection.remote_id().as_bytes())
    }

    /// Checks the authenticated remote key against one paired-device key.
    pub fn ensure_trusted_public_key(
        &self,
        trusted_public_key_hex: &str,
    ) -> Result<(), TransferError> {
        let expected = public_key_from_hex(trusted_public_key_hex)?;
        if self.connection.remote_id() != expected {
            return Err(TransferError::new(
                TransferErrorCode::PeerIdentityChanged,
                "iroh peer does not match the paired device",
                false,
            ));
        }
        Ok(())
    }

    /// Sends one versioned CBOR control message.
    pub async fn send_control(&mut self, message: ControlMessage) -> Result<(), TransferError> {
        let sequence = self
            .sequence
            .checked_add(1)
            .ok_or_else(|| TransferError::invalid("control sequence overflow"))?;
        if self.sequence == 0 {
            self.session_nonce = Some(random_hex(16)?);
        }
        let session_nonce = self
            .session_nonce
            .clone()
            .ok_or_else(|| TransferError::internal("control session nonce is missing"))?;
        let envelope = ControlEnvelope {
            protocol_version: TRANSFER_PROTOCOL_VERSION,
            sequence,
            session_nonce,
            message,
        };
        let encoded = encode_control(&envelope)?;
        write_record(&mut self.control_send, &encoded).await?;
        self.sequence = sequence;
        Ok(())
    }

    /// Receives and validates the next control message.
    pub async fn receive_control(&mut self) -> Result<ControlEnvelope, TransferError> {
        let encoded = read_record(&mut self.control_recv, MAX_CONTROL_MESSAGE_BYTES).await?;
        let envelope = decode_control(&encoded)?;
        match &self.session_nonce {
            Some(expected) if expected != &envelope.session_nonce => {
                return Err(TransferError::invalid("control session nonce changed"));
            }
            Some(_) if envelope.sequence != self.sequence + 1 => {
                return Err(TransferError::invalid("control sequence is not contiguous"));
            }
            None => self.session_nonce = Some(envelope.session_nonce.clone()),
            _ => {}
        }
        self.sequence = envelope.sequence;
        Ok(envelope)
    }

    /// Opens the unidirectional data stream and sends the file header.
    pub async fn send_file_header(
        &mut self,
        header: &FileStreamHeader,
    ) -> Result<(), TransferError> {
        if self.data_send.is_some() {
            return Err(TransferError::invalid("file data stream is already open"));
        }
        let mut stream = self
            .connection
            .open_uni()
            .await
            .map_err(|_| transport_error("iroh file stream open failed"))?;
        let encoded = header.encode()?;
        write_record(&mut stream, &encoded).await?;
        self.data_send = Some(stream);
        Ok(())
    }

    /// Accepts the unidirectional data stream and reads its file header.
    pub async fn receive_file_header(&mut self) -> Result<FileStreamHeader, TransferError> {
        if self.data_recv.is_some() {
            return Err(TransferError::invalid("file data stream is already open"));
        }
        let mut stream = self
            .connection
            .accept_uni()
            .await
            .map_err(|_| transport_error("iroh file stream accept failed"))?;
        let encoded = read_record(&mut stream, MAX_DATA_RECORD_BYTES).await?;
        let header = FileStreamHeader::decode(&encoded)?;
        self.data_recv = Some(stream);
        Ok(header)
    }

    /// Sends one checked file chunk on the unidirectional data stream.
    pub async fn send_chunk(&mut self, frame: &FileChunkFrame) -> Result<(), TransferError> {
        let stream = self
            .data_send
            .as_mut()
            .ok_or_else(|| TransferError::invalid("file data stream is not open"))?;
        let encoded = frame.encode()?;
        write_record(stream, &encoded).await
    }

    /// Receives one checked file chunk from the unidirectional data stream.
    pub async fn receive_chunk(&mut self) -> Result<FileChunkFrame, TransferError> {
        let stream = self
            .data_recv
            .as_mut()
            .ok_or_else(|| TransferError::invalid("file data stream is not open"))?;
        let encoded = read_record(stream, MAX_DATA_RECORD_BYTES).await?;
        FileChunkFrame::decode(&encoded)
    }

    /// Finishes the outbound file stream.
    pub fn finish_file(&mut self) -> Result<(), TransferError> {
        let stream = self
            .data_send
            .as_mut()
            .ok_or_else(|| TransferError::invalid("file data stream is not open"))?;
        stream
            .finish()
            .map_err(|_| transport_error("iroh file stream finish failed"))
    }

    /// Closes the underlying QUIC connection.
    pub fn close(&self) {
        self.connection.close(0_u32.into(), b"transfer complete");
    }
}

async fn write_record(
    stream: &mut (impl AsyncWriteExt + Unpin),
    bytes: &[u8],
) -> Result<(), TransferError> {
    let length = u32::try_from(bytes.len())
        .map_err(|_| TransferError::invalid("wire record is too large"))?;
    stream
        .write_all(&length.to_be_bytes())
        .await
        .map_err(|_| transport_error("iroh stream write failed"))?;
    stream
        .write_all(bytes)
        .await
        .map_err(|_| transport_error("iroh stream write failed"))?;
    Ok(())
}

async fn read_record(
    stream: &mut (impl AsyncReadExt + Unpin),
    maximum: usize,
) -> Result<Vec<u8>, TransferError> {
    let mut length_bytes = [0_u8; 4];
    stream
        .read_exact(&mut length_bytes)
        .await
        .map_err(|_| transport_error("iroh stream read failed"))?;
    let length = usize::try_from(u32::from_be_bytes(length_bytes))
        .map_err(|_| TransferError::invalid("wire record length is invalid"))?;
    if length == 0 || length > maximum {
        return Err(TransferError::invalid("wire record exceeds the size limit"));
    }
    let mut bytes = vec![0_u8; length];
    stream
        .read_exact(&mut bytes)
        .await
        .map_err(|_| transport_error("iroh stream read failed"))?;
    Ok(bytes)
}

fn transport_error(message: impl Into<String>) -> TransferError {
    TransferError::new(TransferErrorCode::TransportOffline, message, true)
}

/// Converts a paired device Ed25519 public key into an iroh EndpointId string.
pub fn endpoint_id_for_public_key(public_key_hex: &str) -> Result<String, TransferError> {
    Ok(public_key_from_hex(public_key_hex)?.to_string())
}

fn public_key_from_hex(public_key_hex: &str) -> Result<PublicKey, TransferError> {
    let bytes = decode_hex_32(public_key_hex, "paired device public key")?;
    PublicKey::from_bytes(&bytes)
        .map_err(|_| TransferError::invalid("paired device public key is invalid"))
}
