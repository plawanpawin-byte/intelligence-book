<!-- job=paper-v11 backend=mlx seconds=276 calls=12 prompt_tokens=12783 gen_tokens=4727 source_chars=10185 source_tokens=2422 note_chars=13055 metrics={'chars': 13055, 'copy_ratio': 0.235, 'fillers': 2, 'dup_headings': 1, 'sections': 7, 'callouts': 21} -->
# The Power of Attention: How Transformers Overcome RNN Weaknesses

Before 2017, sequence tasks like machine translation relied on recurrent neural networks (RNNs). But these models had two significant weaknesses: Computation was inherently sequential, making training non-parallelizable across positions of a sequence. Moreover, information about early tokens must survive many repeated applications of the RNN before it can influence late predictions.

> [!summary] Overview
> Recurrent neural networks (RNNs) were once the go-to model for sequence tasks due to their ability to process sequential data in parallel. However, they suffered from inherent sequential nature and information survival issues, limiting their scalability. The introduction of attention mechanisms revolutionized sequence modeling by replacing recurrence entirely and building the network out of attention and simple feed-forward layers. This innovation led to the development of the Transformer model, which has since become a dominant force in natural language processing tasks.

## The Power of Attention: How Transformers Overcome RNN Weaknesses

Before 2017, sequence tasks like machine translation relied on **recurrent neural networks (RNNs)**. However, these models had two significant weaknesses:

### Sequential Computation and Information Survival
Computation was inherently sequential, making training non-parallelizable across positions of a sequence. Moreover, information about early tokens must survive many repeated applications of the RNN before it can influence late predictions.

> [!warning] The limitations of traditional RNNs
> Inherent sequential nature makes training non-parallelizable · Information survival is crucial for late predictions

### Introducing Attention: A Breakthrough in Sequence Modeling
The **attention mechanism** was introduced as an add-on to recurrent encoder-decoder models (Bahdanau et al., 2015) to address these weaknesses. This innovation revolutionized sequence modeling by replacing recurrence entirely and building the network out of attention and simple feed-forward layers.

### The Transformer's Claim: "Attention Is All You Need"
The Transformer's title, "Attention Is All You Need", summarizes its claim that attention is sufficient for sequence-to-sequence tasks. This bold statement highlights the effectiveness of attention in overcoming traditional RNN limitations.

### How Attention Works
Attention works by comparing a **query** with every key in a dictionary-like store:

- Each comparison produces a similarity score.
- Scores are turned into weights that sum to one.
- Output is the weighted average of all values, where each value contributes proportionally to how well its key matches the query.

> [!tip] Understanding attention's role
> Query-key comparisons produce similarity scores · Weights sum to one · Output is a weighted average

### The Nature of Attention: Retrieval vs. Proportionality
Note that in this system, nothing is ever retrieved "exactly"; instead, every value contributes in proportion to how well its key matches the query.

### Table: Comparison of RNN and Transformer Architectures

|  | RNNs | Transformers |
| --- | --- | --- |
| Computation | Sequential | Parallelizable |
| Information Survival | Difficult | Easy |
| Architecture | Recurrent | Attention-based |

> [!example] The impact of attention on sequence-to-sequence tasks

- [ ] Review the Transformer architecture

## Scaling Attention in Transformer Models

In the Transformer model, three learned linear maps produce **query** vectors for every token i.

### Matrices and Scales
Stacking rows of all n tokens gives matrices Q (n x d_k), K (n x d_k), and V (n x d_v).

The complete operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V.

> [!tip] Understanding attention scales
> Dividing by sqrt(d_k) restores unit variance and keeps softmax in a well-behaved range

### How Attention Works
Reading equation (9.1) from the inside out:

- The product Q K^T measures how strongly token i attends to token j.
- The softmax is applied row by row, so each row becomes a probability distribution over n positions.
- Multiplying by V mixes value vectors according to those probabilities.

### Example: Scaling Attention
Suppose sequence has three tokens and d_k = 4.

Raw scores against keys are (8, 4, 0).

After scaling by 1/sqrt(4) = 0.5, they become (4, 2, 0).

Applying softmax gives weights of approximately (0.87, 0.12, 0.02)

Output for token 1 is therefore 0.87 v_1 + 0.12 v_2 + 0.02 v_3: mostly its own value with a small contribution from token 2

> [!warning] Without scaling, attention becomes "harder"
Without scaling, weights would be about (0.98, 0.02, 0.00), a much "harder" choice

## The Magic of Self-Attention in Transformers

### **Self-Attention**: gathering information from within
In a transformer model, when Q, K, and V are computed from the same sequence, it's called self-attention. ==Every token builds a new representation by gathering info from other tokens in the same sentence==.

This process is crucial for understanding the context of each token, allowing the model to capture complex relationships between words.

### Cross-Attention: bridging the gap between encoder and decoder
In an encoder-decoder model, the decoder uses cross-attention, with queries from the decoder and keys and values from the encoder output. This allows the decoder to understand the context of the input sequence.

> [!tip] Don't look ahead!
The decoder must not predict future tokens; this is enforced with a **causal mask**.
Before softmax, scores (i, j) with j > i are set to minus infinity, making corresponding weights zero.
This mechanism also ignores padding tokens in a batch.

### Masking: preventing future-looking
To prevent language models from looking at future tokens, masking is used. ==Causal mask== prevents the model from considering tokens beyond its current position.

### Multi-Head Attention: specializing relationships
The single attention operation produces one weighted average per token, limiting it to one "kind" of relationship at a time.

> [!example] Different heads learn to specialize
Empirical results show that different heads learn to specialize:
* Some track previous tokens.
* Others link pronouns to nouns they refer to.
* They follow syntactic relations.

However, these interpretations should be treated with caution as heads are not guaranteed to have clean meanings.

### Formula for Multi-Head Attention
The formula for multi-head attention is:

MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O

where head_i = Attention(Q W_i^Q, K W_i^K, V W_i^V)

## Transformer Architecture: Breaking Down Attention Mechanism

The Transformer architecture relies on **Residual connections** that allow gradients to flow directly through dozens of layers, keeping activations stable.

### Residual Connections: The Key to Flowing Gradients

> [!definition] **Residual connections**: keep activations stable and enable gradients to flow through many layers.

### LayerNorm(x + Sublayer(x))
The output is **LayerNorm(x + Sublayer(x))**, where the residual paths let gradients flow directly through many layers. This helps maintain stability in activations.

- [ ] Implement residual connections

### Pre-Normalization for Deep Stacks
Most modern implementations move the normalisation before the sub-layer, making very deep stacks easier to train.

> [!tip] Pre-norm: a crucial step for training deep stacks

### Base Model Architecture
The base model stacks N = 6 such layers in the encoder and 6 in the decoder; the decoder layers additionally contain a cross-attention sub-layer.

- [ ] Understand the base model architecture

### Three Families of Models
Three families of models grew out of this design:

- **Encoder-only models** (e.g. BERT) see the whole input at once and are suited for classification and retrieval.
- **Decoder-only models** (e.g. GPT family) use the causal mask and are trained to predict the next token.
- **Encoder-decoder models** (e.g. T5) keep both halves and are natural for translation and summarization.

> [!example] Self-attention: comparing every token with every other token
Self-attention compares every token with every other token, so its time and memory grow as O(n^2 d) for a sequence of length n.

### Time and Memory Complexity of Self-Attention
The self-attention mechanism has a time and memory complexity of O(n^2 d), making it less efficient for long sequences.

## Transformer Architecture: How Attention Works

### The Cost of Computing Attention
The quadratic cost of computing full self-attention is a major reason early Transformers were limited to contexts of 512 or 1,024 tokens.

For n = 1,000, the score matrix has one million entries per head; for n = 100,000 it would have ten billion. This high computational cost makes efficient attention mechanisms crucial.

### Understanding Attention Mechanism
Attention computes a weighted average of value vectors, with weights given by a softmax over query-key similarities.

> [!definition] **Softmax**: a function that returns a probability distribution over all possible values.

> [!example] Example: "dog bites man" vs "man bites dog"
Without positional encodings, the model cannot distinguish between these two sentences because it doesn't know the order of words.

### Scaling Attention and Multiple Heads
Scaling attention by sqrt(d_k) prevents the softmax from saturating. This is important for preventing the weights from becoming too large.

Multiple heads let the model attend to several relationships at once. For example, if we have 8 heads, each head can focus on a different aspect of the input.

> [!tip] Use multiple heads to improve performance.

> [!example] Example: using 8 heads instead of 1

### Positional Encodings and Word-Order Information
Positional encodings restore word-order information. Without them, the model would not know which words come before or after others.

### Block Structure: Attention + FFN
Each block consists of attention and an FFN (fully connected neural network). Residual connections and LayerNorm are used to improve training stability.

### Efficient Attention Techniques
Techniques include:

* Sparse patterns
* Low-rank approximations
* Memory-efficient exact kernels (e.g. FlashAttention)

These techniques help reduce the computational cost of attention mechanisms.

> [!tip] Use efficient attention techniques for large models.

> [!example] Example: using FlashAttention instead of full self-attention

### Decoder-only Models with KV Cache
Decoder-only models cache the keys and values of previous tokens ("KV cache") during generation, reducing the number of new rows of attention scores needed for each token.

This technique helps improve performance by reducing the computational cost of attention mechanisms.

## Key takeaways
- The Transformer model's attention mechanism is sufficient for sequence-to-sequence tasks because it computes a weighted average of value vectors based on query-key similarities.
- Multiple heads allow the model to attend to several relationships at once, improving its ability to capture complex patterns in data.
- Positional encodings are essential for restoring word-order information and enabling the model to distinguish between different sentence structures.
- Each block of the Transformer consists of an attention operation followed by a fully connected neural network (FFN) layer with residual connections and LayerNorm normalization.
- The cost of full self-attention is quadratic in sequence length, making it computationally expensive for long sequences.

## Review questions

> [!question] Why does the Transformer model's attention mechanism rely on query-key similarities rather than direct comparisons?
> **Answer:** The Transformer model's attention mechanism relies on query-key similarities because direct comparisons would be computationally expensive and difficult to scale, whereas query-key similarities allow for efficient computation using softmax.

> [!question] How do positional encodings help the Transformer model distinguish between different sentence structures?
> **Answer:** Positional encodings help the Transformer model distinguish between different sentence structures by providing word-order information that allows the model to capture subtle differences in sentence structure.

> [!question] What is the main advantage of using multiple heads in the Transformer model's attention mechanism?
> **Answer:** The main advantage of using multiple heads is that it allows the model to attend to several relationships at once, improving its ability to capture complex patterns in data.

> [!question] Why does the Transformer model's self-attention mechanism have a quadratic cost in sequence length?
> **Answer:** The Transformer model's self-attention mechanism has a quadratic cost in sequence length because it computes a weighted average of value vectors for every pair of tokens, resulting in O(n^2 d) complexity.
