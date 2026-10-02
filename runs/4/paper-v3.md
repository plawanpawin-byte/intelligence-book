<!-- job=paper-v3 backend=mlx seconds=197 calls=8 prompt_tokens=9027 gen_tokens=3167 source_chars=10185 source_tokens=2422 note_chars=10191 metrics={'chars': 10191, 'copy_ratio': 0.143, 'fillers': 1, 'dup_headings': 0, 'sections': 5, 'callouts': 16} -->
# The Power of Attention: How Transformers Remember Past Information

"Attention is not just a mechanism, it's a superpower. Transformers use attention to remember past information and make predictions about future ones." With a sequence length of 512 tokens, self-attention mechanisms can be computationally expensive, but they're essential for understanding context in language models.

> [!summary] Overview
> In this note, we'll delve into the world of attention mechanisms in Transformers, exploring how self-attention works, its importance in distinguishing between similar sentences, and why positional encodings are crucial for restoring word-order information. We'll also discuss the block structure of Transformer models, which consists of attention + FFN, with residual connections and LayerNorm. By the end of this journey, you'll understand the magic behind self-attention and how it enables Transformers to remember past information and make predictions about future ones.

## The Power of Attention: How Transformers Remember Past Information

The **attention mechanism** was introduced to address weaknesses in sequential computation and information retention. This is because computation is inherently sequential, making training parallelizable across positions of a sequence.

### Why Attention?
Information about early tokens must survive repeated applications of the model before influencing late predictions. However, traditional dictionary queries are too rigid, either matching exactly or returning no value. Attention relaxes this by allowing each token's input vector to be compared with every key, producing similarity scores that sum to one and weighted averages for output.

> [!tip] Think of attention as a soft dictionary lookup
> Instead of retrieving a single value, all values contribute in proportion to how well their keys match the query.

### Scaled Dot-Product Attention: The Magic Behind Transformers

The Transformer uses the **scaled dot-product attention** mechanism to compute similarities between tokens. This operation is written as:

Q K^T = Measure of token i's attention to token j
softmax(Q K^T) = Probability distribution over n positions for each row
V * softmax(Q K^T) = Output with weights proportional to attention scores
sqrt(d_k) / Q = Restores unit variance and keeps softmax in a well-behaved range

### Example: A Simple Sequence with Three Tokens
Suppose we have a sequence with three tokens, and d_k = 4. For the first token, raw scores against the three keys are (8, 4, 0).

The scaled dot-product attention operation would produce a probability distribution over n positions for each row.

| Token i | Raw Scores |
|---|---|
| 1    | (8, 4, 0) |

- [ ] Understand how attention works in practice

## Attention Weights: how Transformers choose what to look at

Imagine you're trying to decide where to go on a road trip. You have two options: take the highway (fast) or explore the back roads (interesting). In Transformers, **self-attention** is like choosing between these two options.

### Self-Attention: gathering information from other tokens
When Q, K, and V are computed from the same sequence, each token builds a new representation by gathering information from other tokens in the same sentence.

|  | **Without scaling** | **With scaling** |
|---|---|---|
| Weights | (0.98, 0.02, 0.00) | (0.87, 0.12, 0.02) |

> [!tip] Scaling helps with choosing between tokens
> With scaling, attention weights become more balanced, making it easier to choose between tokens.

### Cross-Attention: looking at future tokens is forbidden
In an encoder-decoder model, cross-attention is used with queries coming from the decoder and keys and values coming from the encoder output. But a language model predicting the next token must not look at future tokens; this is enforced with a causal mask before softmax, setting scores (i, j) with j > i to minus infinity.

> [!warning] Causal masking prevents models from looking at future tokens
> This ensures that models don't look at future tokens when predicting the next one.

### Multi-Head Attention: learning multiple relationships simultaneously
Multi-head attention runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace. This produces one weighted average per token, allowing it to learn multiple "kinds" of relationships simultaneously.

|  | **Original base model** |
|---|---|
| d_model = 512 | h = 8 heads |
| d_k = d_v = 64 dimensions |

> [!example] Empirical evidence shows different heads specialize
> Some heads track previous tokens, others link pronouns to nouns, and others follow syntactic relations.

### Positional Information: knowing word order is crucial
Attention is permutation-invariant; without positional encoding, models have no idea of word order unless supplied. The Transformer adds a positional encoding vector to each input embedding using sine and cosine functions of different frequencies.

|  | **Low-dimensional positions** | **High-dimensional positions** |
|---|---|---|
| Oscillate quickly | Distinct patterns for every position |
| Slowly oscillate | More complex relationships |

> [!tip] Many later models learn position embeddings directly or use relative schemes like RoPE
> These schemes allow models to learn more complex relationships between tokens.

## The Magic of Self-Attention: How Transformers Learn

### Weights for the Weighted Average
**Self-attention**: computes a weighted average of value vectors, with weights given by a **softmax over query-key similarities**.

> [!tip] Don't forget to normalize those similarities!
> **Softmax**: ensures weights add up to 1, preventing saturation.

### Scaling Down the Softmax
**Scaling**: uses **sqrt(d_k)** to prevent the softmax from saturating, ensuring weights don't get too big.

| **Term** | **What it does** |
|---|---|
| **Self-attention**: | computes weighted averages of value vectors |
| **Scaling**: | prevents softmax from saturating |
| **Multiple heads**: | attends to multiple relationships at once |

### Restoring Word Order with Positional Encodings
**Positional encodings**: restore word-order information and are essential for distinguishing between sentences like "dog bites man" and "man bites dog".

> [!warning] Without positional encodings, models would get confused!
> **Why is this important?** It's all about understanding the context.

### The Block Structure: Attention + FFN
The block structure consists of **attention + FFN**, with **residual connections** and **LayerNorm**.

| **Block Structure** | **What it does** |
|---|---|
| **Attention**: | computes weighted averages of value vectors |
| **FFN (Fully Connected Neural Network)**: | processes output from attention |

### The Cost of Self-Attention
**Cost of self-attention**: is quadratic in sequence length, which can be a problem for long sequences.

> [!tip] Be aware of the computational cost!

### Calculating Softmax Scores and Determining Token Weights
To answer question 9.1, calculate the softmax scores and determine which tokens receive the largest weights.

> [!example] Practice calculating softmax scores to get better at this!
> **Softmax scores**: show which tokens are most important

### Why Positional Encodings Matter
**Positional encodings**: necessary to distinguish between similar sentences because they provide context clues.

| **Question 9.2 Answer** | **What it does** |
|---|---|
| **Why positional encodings matter?** | restore word-order information |

### Reviewing Worked Example of Section 9.3
Review the worked example in Section 9.3 to solidify your understanding.

> [!tip] Go back and review that example!
> **Worked example**: helps you understand how self-attention works

### Understanding Multiple Heads
**Multiple heads**: allows the model to attend to several relationships at once, improving performance.

> [!example] Practice working with multiple heads to see how it improves results!

### Practicing Calculating Softmax Scores
Practice calculating softmax scores to get better at this important step in self-attention.

## Key takeaways
- The attention mechanism is essential for learning long-range dependencies and information retention in sequential computation models.
- Attention relaxes traditional dictionary queries by producing weighted averages based on similarity scores, allowing multiple values to contribute proportionally.
- Multi-head attention enables the model to attend to several relationships simultaneously, improving its ability to learn complex patterns.
- Positional encodings are necessary to distinguish between similar sentences, as they provide word-order information and help the model understand sentence structure.
- Scaling is crucial in self-attention to prevent the softmax from saturating, ensuring well-behaved learning.

## Review questions
> [!question] Why does the Transformer use the dot product as its similarity function in scaled dot-product attention?
**Answer:** The Transformer uses the dot product as its similarity function because it measures how strongly token i attends to token j, allowing for a weighted average of value vectors according to those probabilities.

> [!question] What is the purpose of multi-head attention in self-attention?
**Answer:** Multi-head attention enables the model to attend to several relationships simultaneously, improving its ability to learn complex patterns and specializing in different types of relationships such as tracking previous tokens or linking pronouns to nouns.

> [!question] Why are positional encodings necessary to distinguish between similar sentences?
**Answer:** Positional encodings are necessary to distinguish between similar sentences because they provide word-order information, helping the model understand sentence structure and distinguish between sentences like "dog bites man" and "man bites dog".

> [!question] How does scaling affect self-attention?
**Answer:** Scaling is crucial in self-attention to prevent the softmax from saturating, ensuring well-behaved learning by restoring unit variance and keeping the softmax in a well-behaved range.
