<!-- job=paper-v10 backend=mlx seconds=279 calls=13 prompt_tokens=13627 gen_tokens=5210 source_chars=10185 source_tokens=2422 note_chars=14713 metrics={'chars': 14713, 'copy_ratio': 0.213, 'fillers': 2, 'dup_headings': 0, 'sections': 8, 'callouts': 20} -->
# The Power of Attention: How Transformers Learned to Look Back

Did you know that before 2017, sequence tasks like machine translation were tackled using **recurrent neural networks (RNNs)**? These models had two major weaknesses: computation was inherently sequential, making training non-parallelizable across positions of a sequence, and information about early tokens must survive many repeated applications of the RNN before it can influence late predictions. But then, the **attention mechanism** was introduced as an add-on to recurrent encoder-decoder models and later became a key component of the Transformer model.

> [!summary] Overview
> The attention mechanism lets the decoder look back at every encoder state and decide which input positions are relevant for each output step, replacing the need for a single summary vector. This is achieved through a process called self-attention, where the model computes attention weights based on similarities between query vectors (Q), key vectors (K), and value vectors (V). By scaling attention with sqrt(d_k) and using multiple heads, the model can attend to several relationships at once, while positional encodings restore word-order information. The Transformer architecture relies on residual connections and LayerNorm for each block to improve performance, enabling it to understand the context of a sentence or passage.

## The Power of Attention: How Transformers Learned to Look Back

Before 2017, sequence tasks like machine translation were tackled using **recurrent neural networks (RNNs)**. However, these models had two major weaknesses:

- Computation was inherently sequential, making training non-parallelizable across positions of a sequence.
- Information about early tokens must survive many repeated applications of the RNN before it can influence late predictions.

### A Breakthrough in Sequence-to-Sequence Models
The **attention mechanism** was introduced as an add-on to recurrent encoder-decoder models and later became a key component of the Transformer model.

> [!tip] Think of attention like a soft dictionary lookup: every value contributes in proportion to how well its key matches the query.

#### How Attention Works

Attention lets the decoder look back at every encoder state and decide which input positions are relevant for each output step. This replaces the need for a single summary vector.

- Each comparison between the query and keys produces a **similarity score**.
- Scores are turned into weights that sum to one, so **every value contributes in proportion to its similarity score**.
- Output is the weighted average of all values, with nothing ever retrieved "exactly".

### The Transformer's Logical Conclusion
The Transformer took attention to its logical conclusion by removing recurrence entirely and building the network out of attention and simple feed-forward layers.

> [!definition] **Transformer**: a neural network architecture that relies solely on self-attention mechanisms and feed-forward neural networks.

#### A Useful Mental Model for Understanding Attention

A useful mental model for understanding attention is to think of it as a soft dictionary lookup. Instead of retrieving values exactly, every value contributes in proportion to how well its key matches the query.

- Scores are turned into weights that sum to one.

### The Claim: "Attention Is All You Need"
The paper's title "Attention Is All You Need" summarizes the claim that attention is sufficient for sequence-to-sequence tasks.

## Scaling Attention in Transformer Models

In the Transformer model, three learned linear maps produce **query** vectors for every token i.

### Building Matrices
Stacking rows of all n tokens gives matrices Q (n x d_k), K (n x d_k), and V (n x d_v).

The complete operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V.

- [ ] Understand how attention works row by row
- [ ] Know the purpose of dividing by sqrt(d_k)

> [!definition] **Softmax**: a function that converts raw scores into probabilities

### How Scaling Attention Works

Reading equation (9.1) from the inside out:

* The product Q K^T measures how strongly token i attends to token j.
* The softmax is applied row by row, so each row becomes a probability distribution over n positions.

Multiplying by V then mixes value vectors according to those probabilities.

- [ ] Understand why dividing by sqrt(d_k) helps
- [ ] Know how scaling attention affects weight choices

### Example: Scaled vs Unscaled Attention

Suppose a sequence has three tokens and d_k = 4. For the first token:

- Raw scores against keys are (8, 4, 0).
- After scaling by 1/sqrt(4) = 0.5, they become (4, 2, 0).
- Applying softmax gives weights of approximately (0.87, 0.12, 0.02).

The output for token 1 is therefore 0.87 v_1 + 0.12 v_2 + 0.02 v_3: mostly its own value, with a small contribution from token 2.

Without scaling, the weights would be about (0.98, 0.02, 0.00), a much "harder" choice.

### Comparison Table

|  | Raw Scores | Scaled Scores |
| --- | --- | --- |
| Q_i | (8, 4, 0) | (4, 2, 0) |
| Softmax | (1, 0, 0) | (0.87, 0.12, 0.01) |

- [ ] Review the importance of attention in Transformer models

## Understanding Self-Attention and Cross-Attention in Transformers

### Self-Attention: gathering information within the same sequence
Self-attention occurs when **Q**, **K**, and **V** are computed from the same sequence. This means each token builds a new representation by gathering information from other tokens in the same sentence.

> [!definition] **Self-attention**: computing Q, K, and V from the same sequence · **Information gathering**: each token represents itself as well as its relationships with other tokens

### Cross-Attention: consultation between encoder and decoder
Cross-attention happens in encoder-decoder models, where the decoder uses its own **Q**, while **K** and **V** come from the encoder's output. This mechanism is used for translation models to consult the source sentence.

> [!example] Translation model: using cross-attention to look up words in the target language
> Consultation: decoder looks at the encoder's output (source sentence) to predict the next token

### Mechanisms to enforce causal relationships
A language model predicting the next token cannot look at future tokens; this is enforced with a **causal mask**:

- Before softmax, scores (**i**, **j**) with **j** > **i** are set to minus infinity, making corresponding weights zero.
- The same mechanism ignores padding tokens in batches.

> [!tip] Causal mask: preventing models from looking ahead · Padding tokens: ignoring irrelevant information

### Single Attention Operation: one "kind" of relationship
Single attention operation produces one weighted average per token, limiting it to one "kind" of relationship at a time.

> [!definition] **Single attention**: computing Q, K, and V for each token individually · Limited relationships: one "kind" of relationship at a time

### Multi-Head Attention: parallel operations in smaller sub-spaces
Multi-head attention runs **h** attention operations in parallel, each with its own projection matrices **W_i^Q**, **W_i^K**, and **W_i^V** that map into smaller sub-spaces.

## The Magic of Self-Attention and Cross-Attention

Transformer models rely on **self-attention** and **cross-attention** operations to process input sequences. Let's dive into how these operations work together.

### How Self-Attention Works
Self-attention is a way for the model to weigh the importance of different tokens in an input sequence. It does this by computing attention weights, which are then used to concatenate the outputs from each attention operation. These concatenated outputs are then passed through a final linear map, **W^O**, to produce the output of the self-attention operation.

> [!example] MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O
> head_i = Attention(Q W_i^Q, K W_i^K, V W_i^V)

### Specialized Heads in Transformer Models

Interestingly, empirically, different heads in a transformer model can learn to specialize. For example:

* Some heads may track **previous tokens** in the sequence.
* Others may link **pronouns** to **nouns** they refer to.
* Others may follow **syntactic relations** between tokens.

However, it's essential to treat these interpretations with caution, as the heads are not guaranteed to have clean meanings.

> [!tip] Be cautious of head specializations
> Heads may learn to track specific patterns or relationships,
> but their meaning is not always clear-cut.

### Cost Comparison

Interestingly, due to smaller dimensions in each head (d_k = d_v = 64), the total cost of using multiple heads can be similar to that of a single full-width head. This is because the computational complexity of self-attention operations scales with the number of attention heads.

> [!warning] Don't get fooled by small dimensions!
> Total cost can be comparable to a single head,
> even with many heads.

### Empirical Evidence

In practice, different heads have been shown to learn and specialize in various ways. However, it's crucial to remember that these interpretations should be treated with caution.

- [ ] Keep this in mind when working with transformer models

## Transformer Architecture: how it works and its attention mechanism

The Transformer architecture uses **Residual connections** and **LayerNorm** for each block to improve performance.

### Building blocks of the Transformer
Each block consists of **Attention** and **FFN (Fully Connected Feedforward Neural Network)**, which work together to enable the model to understand the context of a sentence or passage.

- **Attention**: computes a weighted average of value vectors with weights given by ==a softmax over query-key similarities==.
- To prevent the softmax from saturating, **scaling is done by sqrt(d_k)***.
- **Multiple heads** allow the model to attend to several relationships at once.
- **Positional encodings** restore word-order information.

> [!tip] Scaling for attention
> The softmax function can lead to saturation issues. To mitigate this, we scale it by sqrt(d_k).

### Attention mechanism: how it works
The attention mechanism computes a weighted average of value vectors with weights given by ==a softmax over query-key similarities==.

*   Weights are calculated using a **softmax over query-key similarities**, which allows the model to focus on specific parts of the input sequence.
*   **Scaling is done by sqrt(d_k)** to prevent the softmax from saturating.

> [!example] The importance of positional encodings
> Without positional encodings, a model cannot distinguish "dog bites man" from "man bites dog". This is because word order information is lost, making it impossible for the model to understand the context.

### Limitations of full self-attention

The cost of full self-attention is **quadratic in sequence length**, limiting early Transformers to contexts of 512 or 1,024 tokens.

> [!warning] Attention limitations
> Full self-attention can be computationally expensive. As a result, early Transformers were limited to smaller input sequences.

### Exercises and examples

### Exercise 9.1: Repeat worked example with scores (6, 6, 0) and d_k = 9.
Identify which tokens receive the largest weights.

### Exercise 9.2: Explain why a model without positional encodings cannot distinguish "dog bites man" from "man bites dog".

| **d_k** | **Weights of token 1** |
| --- | --- |
| 9    | 6                     |

> [!definition] Residual connections
> Residual connections are used to improve performance in deep neural networks by adding the identity function back into the equation after each layer.

> [!example] Multiple heads
> Multiple heads allow the model to attend to several relationships at once, improving its ability to understand complex input sequences.

## Transformer Architecture: A Deep Dive

### Residual Connections and Layer Normalization
Every sub-layer in a transformer is wrapped in a residual connection followed by layer normalization: **output = LayerNorm(x + Sublayer(x))**.

> [!definition] **Residual Path**: allows gradients to flow directly through dozens of layers, enabling the training of very deep stacks.

> [!tip] Pre-norm (normalization before the sub-layer) makes very deep stacks easier to train.

### Components of Modern Transformer Models

- **Encoder-only models** (e.g. BERT): see the whole input at once and are suited for classification and retrieval tasks.
- **Decoder-only models** (e.g. GPT family): use the causal mask and are trained to predict the next token; almost all current large language models are of this type.
- **Encoder-decoder models** (e.g. T5): keep both halves and are natural for translation and summarization.

### Computational Cost
Self-attention compares every token with every other token, resulting in a time and memory complexity of O(n^2 d) for a sequence of length n.

> [!warning] **High computational cost**: self-attention is computationally expensive due to its quadratic nature.

### Optimizing Computational Cost

- **Sparse patterns**: reduce the number of comparisons between tokens.
- **Low-rank approximations**: use matrix factorizations to reduce the dimensionality of the attention scores.
- **Memory-efficient exact kernels** (e.g. FlashAttention): optimize the computation of attention scores using specialized algorithms.

### Decoder-only Models: KV Cache
Decoder-only models also cache the keys and values of previous tokens ("KV cache") for faster generation.

> [!example] **Causal Mask**: a key component of decoder-only models, enabling them to predict the next token in a sequence.

### Key Attention Concept

[ ] Review key concepts related to transformer architecture

## Key Takeaways

* The Transformer model's attention mechanism is sufficient for sequence-to-sequence tasks, and it can be thought of as a soft dictionary lookup where every value contributes in proportion to how well its key matches the query.
* Multi-head attention allows the model to attend to several relationships at once, improving its ability to capture complex patterns in data.
* Positional encodings are used to restore word-order information, which is essential for understanding the context and meaning of sequences.

## Review Questions

### Question 1
What is the key insight behind the Transformer model's attention mechanism?

### Question 2
Why does the Transformer model use multi-head attention instead of single-head attention?

### Question 3
What is the purpose of positional encodings in the Transformer model?

### Question 4
Why does the Transformer model use self-attention instead of other attention mechanisms?
