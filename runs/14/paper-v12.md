<!-- job=paper-v12 backend=mlx seconds=301 calls=13 prompt_tokens=13334 gen_tokens=5348 source_chars=10185 source_tokens=2422 note_chars=13121 metrics={'chars': 13121, 'copy_ratio': 0.201, 'fillers': 2, 'dup_headings': 0, 'sections': 7, 'callouts': 17} -->
# The Birth of Attention Mechanism in Transformers
One of the most significant innovations in deep learning is the **attention mechanism**, introduced as an add-on to recurrent encoder-decoder models in 2015. This innovation revolutionized the field of natural language processing, enabling sequence-to-sequence tasks like machine translation to achieve state-of-the-art results.

> [!summary] Overview
> Before 2017, sequence tasks relied on **recurrent neural networks (RNNs)**, which had limitations such as non-parallelizable training and difficulty with long-range dependencies. The attention mechanism addressed these weaknesses by allowing the model to focus on specific relationships between tokens, making it more efficient and effective. This innovation led to the development of the Transformer model, which replaced recurrence entirely with attention and simple feed-forward layers. The Transformer's success marked a significant shift in the way sequence-to-sequence tasks were approached, enabling applications like language translation, text summarization, and question answering.

## The Birth of Attention Mechanism
Before 2017, sequence tasks like machine translation were built from **recurrent neural networks (RNNs)**. However, RNNs had two major weaknesses that hindered their performance.

### Computation and Information Survival
Computation was inherently sequential, making training non-parallelizable across positions of a sequence. This meant that information about early tokens must survive many repeated applications of the RNN before it could influence late predictions.

### Introducing Attention Mechanism
To address these weaknesses, the **attention mechanism** was introduced as an add-on to recurrent encoder-decoder models (Bahdanau et al., 2015). This innovation revolutionized the field of natural language processing.

### The Transformer Revolution
In the Transformer (Vaswani et al., 2017), attention replaced recurrence entirely and built the network out of attention and simple feed-forward layers. This marked a significant shift in the way sequence-to-sequence tasks were approached.

### Attention Is All You Need
The Transformer's title, "Attention Is All You Need", summarizes its claim that attention is sufficient for sequence-to-sequence tasks. This bold statement reflects the model's ability to perform complex tasks without relying on traditional recurrent neural networks.

### How Attention Mechanism Works

Attention works by comparing a **query** with every key in a dictionary-like store:
- Each comparison produces a similarity score.
- Scores are turned into weights that sum to one.
- Output is the weighted average of all values, where each value contributes proportionally to how well its key matches the query.

### Note: Proportional Contributions
In this system, nothing is ever retrieved "exactly"; instead, every value contributes in proportion to how well its key matches the query. This approach allows for efficient and effective processing of sequence data.

**Key Terms:** 
* **Attention Mechanism**: a technique used to weight the importance of different input elements when generating output.
* **Query**: the element that is compared with all keys in the dictionary-like store.
* **Weights**: the scores produced by comparing the query with each key, which sum to one.
* **Proportional Contributions**: every value contributes in proportion to how well its key matches the query.

## Scaling Attention in Transformer Models

The Transformer model uses **scaled dot-product attention** to weigh the importance of different tokens in a sequence.

### Learned Linear Maps
Three learned linear maps produce:
- **Query** q_i = x_i W^Q for every token i
This means that each token's query vector is calculated by multiplying its value vector (x_i) with a weight matrix (W^Q).

### Matrix Form
Stacking rows of all n tokens gives matrices Q (n x d_k), K (n x d_k), and V (n x d_v).
The complete operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V

> [!definition] **Attention Mechanism**
> The attention mechanism measures how strongly token i attends to token j by computing the product Q K^T.

### How Softmax Works
- The softmax is applied row by row, so each row becomes a probability distribution over n positions.
- Multiplying by V mixes value vectors according to those probabilities.

### Scaling for Well-Behaved Range
Dividing by sqrt(d_k) restores unit variance and keeps softmax in a well-behaved range.

### Example: Scaled Attention
Suppose sequence has three tokens and d_k = 4. Raw scores against keys are (8, 4, 0)
After scaling by 1/sqrt(4) = 0.5, they become (4, 2, 0)
Applying softmax gives weights of approximately (0.87, 0.12, 0.02)

> [!tip] Scaling attention helps with **harder choices**
Without scaling, weights would be about (0.98, 0.02, 0.00), a much "harder" choice

### Output
The output for token 1 is therefore 0.87 v_1 + 0.12 v_2 + 0.02 v_3: mostly its own value with a small contribution from token 2

## The Magic of Self-Attention in Transformers

In the world of transformer models, **self-attention** is a powerful mechanism where every token builds a new representation by gathering information from other tokens in the same sentence. This happens when Q, K, and V are computed from the same sequence.

### Cross-Attention: Decoding and Encoder Interaction
But what about interactions between different parts of the model? In an encoder-decoder model, the decoder uses **cross-attention**, with queries coming from the decoder and keys and values coming from the encoder output.

> [!tip] Don't look ahead!
> A language model predicting next token must not look at future tokens; this is enforced with a **causal mask**.

The causal mask ensures that scores (i, j) with j > i are set to minus infinity, making corresponding weights zero. This mechanism also ignores padding tokens in a batch.

### Masking: Preventing Future Sight
To prevent language models from looking at future tokens, **masking** is used. The causal mask achieves this by setting scores (i, j) with j > i to minus infinity, making corresponding weights zero.

> [!warning] Don't trust your interpretations!
> Empirical results show that different heads learn to specialize, but these interpretations should be treated with caution as heads are not guaranteed to have clean meanings.

### Multi-Head Attention: Specialized Relationships

Multi-head attention is a single attention operation that produces one weighted average per token, limiting it to one "kind" of relationship at a time. The formula for multi-head attention is:

MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O
where head_i = Attention(Q W_i^Q, K W_i^K, V W_i^V)

> [!example] Different heads learn different things
> Empirical results show that some heads track previous tokens, others link pronouns to nouns they refer to, and follow syntactic relations.

### Table: Multi-Head Attention Formula

|  | Q  | K  | V  |
| --- | --- | --- | --- |
| head_1 | Q W_1^Q | K W_1^K | V W_1^V |
| ...  | ...   | ...   | ...  |
| head_h | Q W_h^Q | K W_h^K | V W_h^V |

> [ ] Experiment with different attention mechanisms

## Transformer Architecture: A Deep Dive into Attention Mechanism

The Transformer architecture relies on **LayerNorm(x + Sublayer(x))**, where Residual connections allow gradients to flow directly through many layers.

### The Power of Residual Connections
Residual connections keep activations stable, enabling gradients to flow freely through dozens of layers. This is crucial for training deep models.

- [ ] Understand the importance of residual connections in deep learning

### Pre-Normalization: Simplifying Deep Stacks
Most modern implementations move normalisation before sub-layers ("pre-norm"), making very deep stacks easier to train.

> [!tip] Normalise before sub-layer for ease of training

### Base Model Architecture
The base model consists of 6 sub-layers in the encoder and decoder, with additional cross-attention sub-layers in the decoder.

| **Layer** | **Encoder/Decoder** | **Cross-Attention (Decoder only)** |
| --- | --- | --- |
| 1-6 | Encoder/Decoder | No |

### Three Families of Models
Three families of models emerged from this design:

- **Encoder-only models**: e.g. BERT, suited for classification and retrieval.
- **Decoder-only models**: e.g. GPT family, trained to predict the next token using causal mask.
- **Encoder-decoder models**: e.g. T5, natural for translation and summarization.

> [!example] Self-attention's time complexity
> Self-attention compares every token with every other token, resulting in O(n^2 d) time and memory growth for a sequence of length n.

### Time Complexity of Self-Attention
Self-attention's time complexity grows as O(n^2 d), making it less efficient for long sequences.

- [ ] Understand the limitations of self-attention

## Transformer Architecture: The Attention Mechanism Unveiled

### A Costly Computation: Why Early Transformers Were Limited
The **quadratic cost** of computing full self-attention is a major reason early Transformers were limited to contexts of 512 or 1,024 tokens. This high computational cost made it difficult to scale up models.

### Understanding Attention: Weights and Vectors
Attention computes a weighted average of value vectors, with weights given by a softmax over query-key similarities. ==This allows the model to focus on specific relationships between tokens==.

> [!tip] Think of attention as a spotlight that shines on the most relevant information.

> [!example] Scores (6, 6, 0) and d_k = 9: which tokens receive the largest weights?

> [!warning] Without positional encodings, models struggle with word-order information.

### The Role of Positional Encodings
Positional encodings restore word-order information, allowing the model to understand the sequence in which tokens appear. ==This is crucial for distinguishing "dog bites man" from "man bites dog".==

- **9.1**: Repeating the worked example of Section 9.3 with scores (6, 6, 0) and d_k = 9: the largest weights are on the token with a score of 6.

### Multiple Heads and Efficient Attention
Multiple heads let the model attend to several relationships at once, making attention more efficient. ==Scaling by sqrt(d_k) prevents the softmax from saturating, allowing for more accurate computations==.

> [!tip] Think of multiple heads as different lenses that focus on specific aspects of the input.

> [!example] Scaling by sqrt(d_k): how does this prevent the softmax from saturating?

### Block Structure: Attention + FFN
Each block consists of attention and a fully connected neural network (FFN), with residual connections and LayerNorm. ==This structure allows the model to attend to relationships while also leveraging powerful neural networks==.

- [ ] Explore efficient attention techniques, such as sparse patterns or low-rank approximations.

### Decoder-Only Models: KV Cache
Decoder-only models cache the keys and values of previous tokens ("KV cache") during generation, reducing the number of new rows of attention scores needed for each token.

## Key takeaways
- The Transformer model's attention mechanism is sufficient for sequence-to-sequence tasks because it computes a weighted average of value vectors based on query-key similarities.
- Multiple heads allow the model to attend to several relationships at once, improving its ability to generalize and specialize.
- Positional encodings are essential for restoring word-order information in the Transformer model.
- Each block of the Transformer consists of an attention operation followed by a fully connected neural network (FFN) with residual connections and LayerNorm.
- The cost of full self-attention is quadratic in sequence length, making it computationally expensive.

## Review questions

> [!question] Why does the Transformer model's attention mechanism rely on query-key similarities?
> **Answer:** The Transformer model's attention mechanism relies on query-key similarities because it computes a weighted average of value vectors based on these similarities, allowing the model to attend to multiple relationships at once.

> [!question] How do positional encodings improve the performance of the Transformer model?
> **Answer:** Positional encodings improve the performance of the Transformer model by restoring word-order information, enabling the model to understand the sequence structure and make more accurate predictions.

> [!question] What is the main limitation of the Transformer model's self-attention mechanism?
> **Answer:** The main limitation of the Transformer model's self-attention mechanism is that its cost grows quadratically with sequence length, making it computationally expensive for long sequences.

> [!question] How do multiple heads in the Transformer model allow it to generalize and specialize?
> **Answer:** Multiple heads in the Transformer model allow it to generalize and specialize by enabling the model to attend to several relationships at once, improving its ability to learn complex patterns and relationships in the data.
