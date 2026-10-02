<!-- job=paper-v9 backend=mlx seconds=212 calls=10 prompt_tokens=11566 gen_tokens=4128 source_chars=10185 source_tokens=2422 note_chars=12536 metrics={'chars': 12536, 'copy_ratio': 0.235, 'fillers': 2, 'dup_headings': 0, 'sections': 7, 'callouts': 23} -->
# The Power of Attention: How it Revolutionized NLP Models
One of the most significant breakthroughs in Natural Language Processing (NLP) is the introduction of attention mechanisms in deep learning models. This innovation allowed recurrent neural networks (RNNs) to learn long-range dependencies, leading to a substantial improvement in their performance.

> [!summary] Overview
> Attention mechanisms were introduced to address the weaknesses of traditional RNNs in learning long-range dependencies. The Transformer model, built around attention and simple feed-forward layers, revolutionized the field by removing recurrence entirely. Attention can be thought of as a way to find similarities between each token's vector and every key, producing similarity scores that are turned into weights that sum to one. Multi-head attention is used in many modern models, where each head works with 64 dimensions, allowing the model to learn from different aspects of the input and improving its ability to capture complex patterns in data.

## The Power of Attention: How it Changed the Game for NLP Models

The attention mechanism was introduced to address the weaknesses of traditional RNNs in learning long-range dependencies. **Bahdanau et al., 2015** showed that recurrent encoder-decoder models could benefit from this addition.

### A Revolutionary Breakthrough
The Transformer, built around attention and simple feed-forward layers, revolutionized the field by removing recurrence entirely. **Vaswani et al., 2017** demonstrated its potential with a groundbreaking model.

> [!definition] Attention as a soft dictionary lookup
Attention can be thought of as a way to find similarities between each token's vector and every key, producing similarity scores that are turned into weights that sum to one.

### How it Works: The Three Learned Linear Maps
Each token's vector produces three learned linear maps:

- **Query (Q)**: q_i = x_i W^Q
- **Key (K)**: k_i = x_i W^K
- **Value (V)**: v_i = x_i W^V

The complete operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V.

> [!example] A worked example with raw scores
Suppose a sequence has three tokens and d_k = 4. For the first token, the raw scores against the three keys are (8, 4, 0).

### The Magic of Softmax and Dot Product
The dot product is used as the similarity function, resulting in an n x n matrix whose entry (i, j) measures how strongly token i attends to token j. The softmax is applied row by row, so each row becomes a probability distribution over the n positions.

> [!tip] Don't forget about the importance of dividing by sqrt(d_k)
Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range, preventing gradients from shrinking or exploding.

### Table: Raw Scores Against Keys
|  | Key 1 | Key 2 | Key 3 |
| --- | --- | --- | --- |
| Token 1 | 8   | 4    | 0    |

- [ ] Now you know the secrets behind attention mechanisms!

## Attention Mechanism in Transformers: How it Works and Why It Matters

### Scaling Down Attention Weights
When attention weights are scaled by 1/sqrt(4) = 0.5, the output for a token becomes approximately its own value plus a small contribution from another token.

- **Before scaling**: (0.98, 0.02, 0.00), making it a "harder" choice.
- **After scaling**: (0.87, 0.12, 0.02)

> [!tip] Scaling down attention weights helps to make the model more interpretable and easier to understand

### Self-Attention: Gathering Information in the Same Sentence
Self-attention occurs when Q, K, and V are computed from the same sequence, where every token builds a new representation by gathering information from other tokens in the same sentence.

> [!definition] **Self-attention**: computing Q, K, and V from the same sequence

### Cross-Attention: Encoder-Decoder Communication
Cross-attention is used in encoder-decoder models, where queries come from the decoder and keys and values come from the encoder output.

> [!example] **Cross-attention**: enabling communication between the encoder and decoder

### Masking to Prevent Future Tokens
Masking is enforced to prevent language models from looking at future tokens; this is done with a causal mask that sets scores (i, j) with j > i to minus infinity.

> [!warning] **Masking**: preventing language models from accessing future tokens

### Multi-Head Attention: Running Multiple Attention Operations in Parallel
Multi-head attention runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace.

> [!tip] **Multi-head attention**: running multiple attention operations in parallel for better performance and interpretability

### Output Concatenation and Final Linear Map
The outputs are concatenated and passed through a final linear map W^O: MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O.

## Understanding Multi-Head Attention in Transformers

### Breaking Down the Transformer's Attention Mechanism
The original base model uses **multi-head attention**, where each head works with **64 dimensions**. This is achieved by dividing the input into 8 heads, each working with **d_k = d_v = 64** dimensions.

> [!definition] **Multi-head attention**: allows different heads to focus on different parts of the input simultaneously

### Empirical Results Show Specialization Across Heads
Empirical results show that each head learns to specialize in tracking previous tokens, linking pronouns to nouns, or following syntactic relations. ==This specialization leads to better performance==.

- [ ] Understand how multi-head attention helps the model learn from different aspects of the input

### The Importance of Positional Encoding
Without positional encoding, the model has no idea of word order unless it's supplied. **Attention is permutation-invariant**, meaning it doesn't care about the order of the input.

> [!tip] Don't forget about positional encoding
> Without it, the model would have no way of knowing the order of tokens

### How Positional Encoding Works
Positional encoding vectors are added to input embeddings using sine and cosine functions of different frequencies.

- **PE(pos, 2i) = sin(pos / 10000^(2i/d_model))**: low dimensions oscillate quickly
- **PE(pos, 2i+1) = cos(pos / 10000^(2i/d_model))**: high dimensions oscillate slowly

> [!example] Every position receives a distinct pattern
> This helps the model understand the order of tokens

### Later Models Learn Directly from Positional Information
Many later models learn position embeddings directly or use relative schemes like RoPE, which rotate query and key vectors by an angle proportional to their position.

> [!warning] Be aware of changes in positional encoding schemes
> These can impact performance and understanding of the model

## The Power of Self-Attention: How Transformers Learn

### A Deep Dive into the Transformer's Inner Workings
The inner dimension of the Feed Forward Neural Network (FFN) is usually four times d_model. This means that in the base model, **d_model** = 512, and the FNN's inner dimension is **2048**, which is four times 512.

### Moving Information Between Positions
Self-attention moves information between positions, while the FFN processes the information at each position. Think of it like a messenger system: attention sends messages between tokens, and the FFN processes those messages individually.

> [!definition] **Attention**: compares every token with every other token

### Residual Connections and Layer Normalization
Each sub-layer is wrapped in a residual connection followed by layer normalization: the output is **LayerNorm(x + Sublayer(x))**. This setup lets gradients flow directly through dozens of layers, while keeping activations stable with **normalisation**.

> [!tip] Pre-norm makes very deep stacks easier to train

### The Anatomy of a Transformer Layer
Most modern implementations move the normalisation before the sub-layer ("pre-norm"), which makes very deep stacks easier to train. The base model stacks N = 6 such layers in the encoder and 6 in the decoder; the decoder layers additionally contain a cross-attention sub-layer.

### Three Families of Models
Three families of models grew out of this design: **Encoder-only** models (e.g. BERT), **Decoder-only** models (e.g. GPT family), and **Encoder-decoder** models (e.g. T5).

### Computational Cost
The self-attention mechanism has a high computational cost: it compares every token with every other token, so its time and memory grow as O(n^2 d) for a sequence of length n.

> [!warning] High computational cost
> For n = 1,000 the score matrix has one million entries per head; for n = 100,000 it would have ten billion.

### A Table to Compare

| Model Type | Description |
| --- | --- |
| Encoder-only | Focuses on input encoding (e.g. BERT) |
| Decoder-only | Focuses on output decoding (e.g. GPT family) |
| Encoder-decoder | Balances both input and output processing (e.g. T5) |

- [ ] Review the three families of models

## Self-Attention Mechanism in Transformers: how it works and its limitations

**Recurrent layers vs. self-attention**: Recurrent layers are computationally expensive because they require sequential computation of O(n*d^2). This is why early Transformers were limited to short contexts, such as 512 or 1,024 tokens.

### Efficient attention mechanisms
To overcome the quadratic cost of full self-attention, efficient attention mechanisms include:

* Sparse patterns: reducing the number of weights by only considering relevant positions.
* Low-rank approximations: using a lower-dimensional representation to reduce computational costs.
* Memory-efficient exact kernels like FlashAttention: optimized for specific use cases.

> [!definition] Self-Attention Mechanism
> Attention computes a weighted average of value vectors with weights given by a softmax over query-key similarities.

### Multiple heads and positional encodings

Multiple heads allow the model to attend to several relationships at once, improving its ability to capture complex patterns in data. Positional encodings restore word-order information, which is essential for understanding the context of sentences like "dog bites man" vs. "man bites dog".

Each block consists of attention + FFN (fully connected neural network), with residual connections and LayerNorm (a technique to normalize the output).

> [!warning] Quadratic cost
> The full self-attention mechanism has a quadratic cost in sequence length.

### Exercises

1: **Compute largest weights**
Repeat the worked example of Section 9.3 with scores (6, 6, 0) and d_k = 9. Which tokens receive the largest weights?

2: **Positional encodings matter**
Explain why a model without positional encodings cannot distinguish "dog bites man" from "man bites dog".

> [!tip] Understand the importance of positional encodings
> Without them, the model would not be able to capture word-order information.

- [ ] Review self-attention mechanisms

## Key takeaways
The attention mechanism is a crucial component of Transformer models, allowing them to focus on specific tokens and relationships within a sequence.

• Attention can be thought of as a soft dictionary lookup, where each token's vector is compared with every key.
• The Transformer model built its network around attention and simple feed-forward layers, removing recurrence entirely.
• Multiple heads let the model attend to several relationships at once.

## Review questions

> [!question] What is the main advantage of using multiple heads in Transformer models?
> **Answer:** Using multiple heads allows the model to attend to several relationships at once, making it more robust and effective in capturing complex patterns in data.

> [!question] Why do recurrent layers have a higher computational cost than self-attention mechanisms?
> **Answer:** Recurrent layers must be computed sequentially, resulting in a quadratic cost of O(n d^2) compared to the linear cost of O(n d) for self-attention mechanisms.

> [!question] How does the attention mechanism compare every token with every other token?
> **Answer:** The attention mechanism compares every token with every other token, resulting in an n x n matrix whose entry (i, j) measures how strongly token i attends to token j.

> [!question] What is the purpose of masking in language models?
> **Answer:** Masking is enforced to prevent language models from looking at future tokens; this is done with a causal mask that sets scores (i, j) with j > i to minus infinity.
